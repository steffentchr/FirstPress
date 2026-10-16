import Foundation
import PressingCore

/// Records what the core asks of the Phone output.
@MainActor
final class FakePhoneOutput: PhoneOutput {
    /// The switch as the adapter was last told it.
    private(set) var isSwitchedOn = false
    private(set) var isPlaying = false
    /// Every buffer handed over to play, in order.
    private(set) var played: [PCMBuffer] = []

    func switched(on: Bool) { isSwitchedOn = on }
    func start() { isPlaying = true }
    func stop() { isPlaying = false }
    func play(_ buffer: PCMBuffer) { played.append(buffer) }

    /// Seconds of audio handed over so far.
    var playedSeconds: Double {
        played.reduce(0) { $0 + Double($1.frameCount) / $1.sampleRate }
    }
}
