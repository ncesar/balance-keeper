// Self-check: with the app running, moves the balance to the left and checks it goes back to center.
// Usage: swift scripts/check.swift
import AudioToolbox
import Foundation

var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var dev = AudioObjectID(0)
var size = UInt32(MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)

var bal = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
    mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
var left: Float32 = 0
var fsize = UInt32(MemoryLayout<Float32>.size)
assert(AudioHardwareServiceSetPropertyData(dev, &bal, 0, nil, fsize, &left) == noErr, "device doesn't support balance")
Thread.sleep(forTimeInterval: 1)
var now: Float32 = -1
AudioHardwareServiceGetPropertyData(dev, &bal, 0, nil, &fsize, &now)
print("balance after 1s:", now)
assert(abs(now - 0.5) < 0.01, "FAILED: balance didn't go back to center")
print("OK")
