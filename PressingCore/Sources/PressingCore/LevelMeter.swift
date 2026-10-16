import Foundation

/// Turns captured stereo audio into levels: one RMS level in dBFS per ~100 ms frame.
///
/// The frame length follows the buffer's sample rate, so 44.1 and 48 kHz
/// inputs measure the same.
struct LevelMeter {
    static let frameSeconds = 0.1

    private var sumOfSquares: Double = 0
    private var samplesInFrame = 0
    private var sampleRate: Double?

    /// Adds a buffer and returns the level of every frame it completed.
    mutating func add(_ buffer: PCMBuffer) -> [Double] {
        if sampleRate != buffer.sampleRate {
            reset()
            sampleRate = buffer.sampleRate
        }
        let frameLength = Int((buffer.sampleRate * Self.frameSeconds).rounded())
        var levels: [Double] = []
        for i in 0..<buffer.frameCount {
            let l = Double(buffer.left[i])
            let r = Double(buffer.right[i])
            sumOfSquares += l * l + r * r
            samplesInFrame += 1
            if samplesInFrame == frameLength {
                let rms = (sumOfSquares / Double(2 * frameLength)).squareRoot()
                levels.append(Self.dBFS(rms))
                sumOfSquares = 0
                samplesInFrame = 0
            }
        }
        return levels
    }

    mutating func reset() {
        sumOfSquares = 0
        samplesInFrame = 0
        sampleRate = nil
    }

    static func dBFS(_ rms: Double) -> Double {
        guard rms > 0 else { return InputState.minimumLevel }
        return max(20 * log10(rms), InputState.minimumLevel)
    }
}
