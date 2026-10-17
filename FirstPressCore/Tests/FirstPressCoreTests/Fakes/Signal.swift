import Foundation
import FirstPressCore

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
    /// Feeds mono samples in 512-frame buffers, the way a USB input delivers
    /// them, all at once: no time passes.
    func feed(_ samples: [Float], sampleRate: Double, from inputID: AudioInputDevice.ID = AudioInputDevice.deck.id) {
        feed(samples, sampleRate: sampleRate, from: inputID) { _ in }
    }

    /// Plays mono samples in real time: each 512-frame buffer arrives once the
    /// scheduler has moved on by that buffer's duration.
    func play(_ samples: [Float], sampleRate: Double, on scheduler: FakeScheduler) {
        feed(samples, sampleRate: sampleRate, from: AudioInputDevice.deck.id) { frames in
            scheduler.advance(by: Double(frames) / sampleRate)
        }
    }

    private func feed(
        _ samples: [Float],
        sampleRate: Double,
        from inputID: AudioInputDevice.ID,
        beforeEachBuffer: (Int) -> Void
    ) {
        let chunk = 512
        var start = 0
        while start < samples.count {
            let end = min(start + chunk, samples.count)
            beforeEachBuffer(end - start)
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
