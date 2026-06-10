// Records from the default input (mic) for ~3 seconds and prints the peak
// RMS level, scaled so silence is ~0 and conversation-level sound is >1.
import AVFoundation
import Foundation

let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
var peakRMS: Float = 0

input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    guard let data = buffer.floatChannelData?[0] else { return }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return }
    var sum: Float = 0
    for i in 0..<n { sum += data[i] * data[i] }
    let rms = sqrtf(sum / Float(n))
    if rms > peakRMS { peakRMS = rms }
}

do {
    try engine.start()
} catch {
    print("ERROR: could not start input: \(error)")
    exit(2)
}

Thread.sleep(forTimeInterval: 3.0)
engine.stop()
print(String(format: "peakRMS=%.5f", peakRMS * 100))
