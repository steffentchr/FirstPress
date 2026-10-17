import PressingCore
import PressingMenuCore

/// The Mac's notifications: records each one Pressing Menu posts.
@MainActor
final class FakeMenuNotifier: MenuNotifier {
    /// The Tracks that got a notification, in order.
    private(set) var notified: [Track] = []

    func notify(newTrack track: Track) { notified.append(track) }
}
