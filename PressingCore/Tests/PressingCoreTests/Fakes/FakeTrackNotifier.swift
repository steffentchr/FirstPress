import PressingCore
import PressingMenuCore

/// The Mac's notifications: records each Track Pressing Menu posts one for.
@MainActor
final class FakeTrackNotifier: TrackNotifier {
    private(set) var notified: [Track] = []

    func notify(newTrack track: Track) { notified.append(track) }
}
