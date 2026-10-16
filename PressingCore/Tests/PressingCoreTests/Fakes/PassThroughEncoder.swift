import Foundation
import PressingCore

/// MP3Encoder fake: each "frame" is the left channel's 1152 samples as raw
/// Float32 bytes, so a test can read back exactly which audio a client got.
@MainActor
final class PassThroughEncoder: MP3Encoder {
    private var pending: [Float] = []
    /// Every sample handed to the encoder, after resampling.
    private(set) var received: [Float] = []

    func encode(left: [Float], right: [Float]) -> [Data] {
        received += left
        pending += left
        var frames: [Data] = []
        while pending.count >= MP3.samplesPerFrame {
            let frame = Array(pending.prefix(MP3.samplesPerFrame))
            pending.removeFirst(MP3.samplesPerFrame)
            frames.append(frame.withUnsafeBufferPointer { Data(buffer: $0) })
        }
        return frames
    }

    /// Reads back samples the fake encoded.
    static func samples(in data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
