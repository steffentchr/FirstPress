import Foundation
import PressingCore

/// Test signals, fed to a FakeAudioInput in hardware-sized buffers.
enum Signal {
    /// A square wave of the given peak amplitude. Its RMS equals its amplitude,
    /// so its level is exactly 20·log10(amplitude) dBFS.
    static func square(amplitude: Float, seconds: Double, sampleRate: Double) -> [Float] {
        let count = Int((seconds * sampleRate).rounded())
        return (0..<count).map { $0 % 2 == 0 ? amplitude : -amplitude }
    }

    /// Silence with one full-scale sample (a click) at each given second.
    static func clicks(at seconds: [Double], over duration: Double, floor: Float, sampleRate: Double) -> [Float] {
        var samples = square(amplitude: floor, seconds: duration, sampleRate: sampleRate)
        for second in seconds {
            let index = Int(second * sampleRate)
            if index < samples.count { samples[index] = 1 }
        }
        return samples
    }
}

extension FakeAudioInput {
    /// Feeds mono samples in 512-frame buffers, the way a USB input delivers them.
    func feed(_ samples: [Float], sampleRate: Double, from inputID: AudioInputDevice.ID = AudioInputDevice.deck.id) {
        let chunk = 512
        var start = 0
        while start < samples.count {
            let end = min(start + chunk, samples.count)
            let buffer = PCMBuffer(
                inputID: inputID,
                sampleRate: sampleRate,
                time: Double(start) / sampleRate,
                channels: [Array(samples[start..<end])]
            )
            send(.buffer(buffer))
            start = end
        }
    }
}
