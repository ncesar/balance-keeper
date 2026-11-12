// Self-check: com o app rodando, joga o balanço pra esquerda e confere se voltou pro centro.
// Uso: swift check.swift
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
assert(AudioHardwareServiceSetPropertyData(dev, &bal, 0, nil, fsize, &left) == noErr, "dispositivo não suporta balanço")
Thread.sleep(forTimeInterval: 1)
var now: Float32 = -1
AudioHardwareServiceGetPropertyData(dev, &bal, 0, nil, &fsize, &now)
print("balanço após 1s:", now)
assert(abs(now - 0.5) < 0.01, "FALHOU: balanço não voltou pro centro")
print("OK")
