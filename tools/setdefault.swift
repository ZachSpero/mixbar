// Sets the system default output device by UID substring match.
import CoreAudio
import Foundation

let targetUID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "BuiltInSpeakerDevice"

var addr = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices)

for dev in devices {
    var uidAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var uid: CFString = "" as CFString
    var uidSize = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &uid) { ptr -> OSStatus in
        AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &uidSize, ptr)
    }
    guard status == noErr else { continue }
    if (uid as String).contains(targetUID) {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = dev
        let s = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil,
                                           UInt32(MemoryLayout<AudioObjectID>.size), &devID)
        print(s == noErr ? "default set to \(uid)" : "failed: \(s)")
        exit(s == noErr ? 0 : 1)
    }
}
print("device not found: \(targetUID)")
exit(1)
