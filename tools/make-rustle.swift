// Writes art/rustle.caf: a soft, one-second leaf rustle synthesized from shaped noise, so no recording or license is
// involved. Run from the repo: swift tools/make-rustle.swift
import AVFoundation

let rate = 44_100.0, seconds = 1.1
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let frames = AVAudioFrameCount(rate * seconds)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
buffer.frameLength = frames
var rng = SystemRandomNumberGenerator()
var low = 0.0, band = 0.0, crackle = 0.0
let samples = buffer.floatChannelData![0]
for i in 0..<Int(frames) {
    let t = Double(i) / rate
    let white = Double.random(in: -1...1, using: &rng)
    // A state-variable band-pass around 3 kHz: dry leaves, not hiss.
    let f = 2 * sin(Double.pi * 3_000 / rate), q = 0.9
    low += f * band
    let high = white - low - q * band
    band += f * high
    // Bursts of crackle, the leaves brushing each other, fading in and out.
    if Double.random(in: 0...1, using: &rng) < 0.004 { crackle = Double.random(in: 0.5...1, using: &rng) }
    crackle *= 0.9985
    let envelope = sin(Double.pi * min(1, t / seconds)) * (0.35 + 0.65 * crackle)
    samples[i] = Float(band * envelope * 0.22)
}
let url = URL(filePath: "art/rustle.caf")
try? FileManager.default.removeItem(at: url)
let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
try file.write(from: buffer)
print("Wrote \(url.path)")
