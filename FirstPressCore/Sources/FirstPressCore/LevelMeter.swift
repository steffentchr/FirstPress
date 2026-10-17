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

/// The click-robust level: the median of the last second of frame levels.
///
/// An isolated click lifts one ~100 ms frame and leaves the median alone, so
/// the run-out groove's click every 1.8 s (1.33 s at 45 rpm) neither holds a
/// Record open nor stops a Flip.
struct LevelWindow {
    static let seconds = 1.0

    private var levels: [Double] = []
    private let capacity = Int((seconds / LevelMeter.frameSeconds).rounded())

    /// Adds one frame level and returns the median of the window so far.
    mutating func add(_ level: Double) -> Double {
        levels.append(level)
        if levels.count > capacity {
            levels.removeFirst(levels.count - capacity)
        }
        return Self.median(levels)
    }

    mutating func reset() {
        levels = []
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
