import Foundation

/// Tracks the level during silence so the start threshold can be calibrated
/// above the run-out groove and any ground-loop hum.
///
/// Silence means a frame below the start threshold. The noise floor is the
/// median of the most recent ten seconds of silent frames, so an isolated
/// click neither lifts it nor counts as silence.
struct NoiseFloor {
    static let windowSeconds = 10.0

    /// The start threshold, in dBFS, from Settings.
    var threshold: Double

    private var silentLevels: [Double] = []
    private let capacity = Int(windowSeconds / LevelMeter.frameSeconds)

    init(threshold: Double) {
        self.threshold = threshold
    }

    /// Adds one frame level and returns the current noise floor, if any.
    mutating func add(_ level: Double) -> Double? {
        if level < threshold {
            silentLevels.append(level)
            if silentLevels.count > capacity {
                silentLevels.removeFirst(silentLevels.count - capacity)
            }
        }
        return value
    }

    var value: Double? {
        guard !silentLevels.isEmpty else { return nil }
        let sorted = silentLevels.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
