import AppKit
import AudioToolbox
import ServiceManagement

// Keeps the L/R balance of the default output device always centered (0.5).
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let stateItem = NSMenuItem(title: "Keep Centered", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var device = AudioObjectID(kAudioObjectUnknown)
    var deviceName = "?"
    var deviceChangedAt = Date.distantPast
    var lastFix: Date?
    var paused = UserDefaults.standard.bool(forKey: "paused")

    var balanceAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    var defaultAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // C listener: called when another app changes the balance.
    let onBalance: AudioObjectPropertyListenerProc = { _, _, _, ctx in
        let app = Unmanaged<App>.fromOpaque(ctx!).takeUnretainedValue()
        DispatchQueue.main.async { app.center() }
        return noErr
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "BalanceKeeper")
        item.menu = menu
        menu.delegate = self

        menu.addItem(.sectionHeader(title: "BalanceKeeper"))
        stateItem.target = self
        menu.addItem(stateItem)
        menu.addItem(.separator())
        loginItem.target = self
        loginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(loginItem)
        let logItem = menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        logItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Output device changed (BT headphones, HDMI...) → re-attach the listener.
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main) { [weak self] _, _ in
            self?.deviceChangedAt = Date()
            self?.attach()
        }
        attach()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func toggle() {
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "paused")
        refresh()
        center()
    }

    func refresh() {
        item.button?.appearsDisabled = paused
        stateItem.state = paused ? .off : .on
        let fix = lastFix.map { "last fix at \($0.formatted(date: .omitted, time: .shortened))" }
        stateItem.subtitle = paused ? "Paused" : "\(deviceName) · \(fix ?? "no fixes yet")"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func attach() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if device != kAudioObjectUnknown {
            AudioHardwareServiceRemovePropertyListener(device, &balanceAddr, onBalance, ctx)
        }
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, &size, &device)
        AudioHardwareServiceAddPropertyListener(device, &balanceAddr, onBalance, ctx)
        let name = read(device, kAudioObjectPropertyName, Unmanaged<CFString>?.none)?.takeRetainedValue()
        deviceName = name.map { $0 as String } ?? "?"
        refresh()
        center()
    }

    func center() {
        guard !paused else { return }
        var b: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        // Device without balance (e.g. some HDMI outputs) → nothing to do.
        guard AudioHardwareServiceGetPropertyData(device, &balanceAddr, 0, nil, &size, &b) == noErr,
              abs(b - 0.5) > 0.001 else { return }
        var c: Float32 = 0.5
        AudioHardwareServiceSetPropertyData(device, &balanceAddr, 0, nil, size, &c)
        lastFix = Date()
        refresh()
        // macOS doesn't tell who changed the balance, so we log the suspects.
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let apps = audioApps()
        let switched = Date().timeIntervalSince(deviceChangedAt) < 5 ? "  [right after output change]" : ""
        log(String(format: "%.2f → 0.50  %@  focus: %@  audio: %@%@", b, deviceName, front,
                   apps.isEmpty ? "none" : apps.joined(separator: ", "), switched))
    }

    // Apps playing audio right now (macOS 14+), no duplicates.
    func audioApps() -> [String] {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids)
        let names = ids.filter { read($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 }.map {
            let pid = read($0, kAudioProcessPropertyPID, pid_t(0))
            if let n = NSRunningApplication(processIdentifier: pid)?.localizedName { return n }
            var buf = [CChar](repeating: 0, count: 256)  // helpers/daemons without an app
            proc_name(pid, &buf, 256)
            return String(cString: buf)
        }
        return Array(Set(names)).sorted()
    }

    func read<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ initial: T) -> T {
        var a = AudioObjectPropertyAddress(mSelector: sel,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = initial
        var s = UInt32(MemoryLayout<T>.size)
        AudioObjectGetPropertyData(obj, &a, 0, nil, &s, &v)
        return v
    }

    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BalanceKeeper.log")

    // One line per fix; keeps only the last 500.
    func log(_ msg: String) {
        let old = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let stamp = Date().formatted(date: .numeric, time: .standard)
        let lines = old.split(separator: "\n").suffix(499).map(String.init) + ["\(stamp)  \(msg)"]
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    @objc func openLog() {
        // No fixes yet → file doesn't exist and open fails silently.
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(logURL)
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        try? s.status == .enabled ? s.unregister() : s.register()
        refresh()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
