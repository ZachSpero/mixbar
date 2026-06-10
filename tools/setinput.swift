import CoreAudio
import Foundation
let targetUID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MixBarDevice"
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var devs = [AudioObjectID](repeating: 0, count: Int(size)/4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devs)
for d in devs {
    var ua = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var u: CFString = "" as CFString
    var us = UInt32(MemoryLayout<CFString>.size)
    guard withUnsafeMutablePointer(to: &u, { AudioObjectGetPropertyData(d, &ua, 0, nil, &us, $0) }) == noErr else { continue }
    if (u as String) == targetUID {
        var da = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = d
        let s = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &da, 0, nil, 4, &dev)
        print(s == noErr ? "input set to \(u)" : "failed \(s)")
        exit(s == noErr ? 0 : 1)
    }
}
print("not found")
exit(1)
