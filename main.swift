import AppKit
import AudioToolbox
import ServiceManagement

// Mantém o balanço L/R do dispositivo de saída padrão sempre no centro (0.5).
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let stateItem = NSMenuItem(title: "Manter centralizado", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Abrir no login", action: #selector(toggleLogin), keyEquivalent: "")
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

    // Listener C: chamado quando outro app mexe no balanço.
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
        let logItem = menu.addItem(withTitle: "Abrir log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        logItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Troca de dispositivo (fone BT, HDMI...) → reanexa o listener.
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
        let fix = lastFix.map { "última correção às \($0.formatted(date: .omitted, time: .shortened))" }
        stateItem.subtitle = paused ? "Pausado" : "\(deviceName) · \(fix ?? "nenhuma correção")"
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
        // Dispositivo sem balanço (ex.: algumas saídas HDMI) → nada a fazer.
        guard AudioHardwareServiceGetPropertyData(device, &balanceAddr, 0, nil, &size, &b) == noErr,
              abs(b - 0.5) > 0.001 else { return }
        var c: Float32 = 0.5
        AudioHardwareServiceSetPropertyData(device, &balanceAddr, 0, nil, size, &c)
        lastFix = Date()
        refresh()
        // O macOS não informa quem mudou o balanço; registramos os suspeitos.
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let apps = audioApps()
        let switched = Date().timeIntervalSince(deviceChangedAt) < 5 ? "  [logo após trocar saída]" : ""
        log(String(format: "%.2f → 0.50  %@  foco: %@  áudio: %@%@", b, deviceName, front,
                   apps.isEmpty ? "nenhum" : apps.joined(separator: ", "), switched))
    }

    // Apps com saída de áudio ativa agora (macOS 14+), sem repetição.
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
            var buf = [CChar](repeating: 0, count: 256)  // helpers/daemons sem app
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

    // Uma linha por correção; guarda só as últimas 500.
    func log(_ msg: String) {
        let old = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let stamp = Date().formatted(date: .numeric, time: .standard)
        let lines = old.split(separator: "\n").suffix(499).map(String.init) + ["\(stamp)  \(msg)"]
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    @objc func openLog() {
        // Sem correções ainda → arquivo não existe e o open falha calado.
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
