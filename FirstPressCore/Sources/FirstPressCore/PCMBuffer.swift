import Foundation

/// Timestamped stereo float PCM at the input's native sample rate.
public struct PCMBuffer: Sendable, Equatable {
    public let inputID: AudioInputDevice.ID
    public let sampleRate: Double
    /// Host time of the first frame, in seconds.
    public let time: TimeInterval
    public let left: [Float]
    public let right: [Float]

    /// Builds a stereo buffer from deinterleaved channels. A mono input is
    /// duplicated to both sides; channels beyond the second are dropped.
    public init(inputID: AudioInputDevice.ID, sampleRate: Double, time: TimeInterval, channels: [[Float]]) {
        self.inputID = inputID
        self.sampleRate = sampleRate
        self.time = time
        let left = channels.first ?? []
        self.left = left
        self.right = channels.count > 1 ? channels[1] : left
    }

    public var frameCount: Int { left.count }
}
