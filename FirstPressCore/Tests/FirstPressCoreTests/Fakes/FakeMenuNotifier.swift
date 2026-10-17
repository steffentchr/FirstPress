import FirstPressCore
import FirstPressMenuCore

/// The Mac's notifications: records each one First Press Menu posts, and
/// whether a "Flip the record" notification is still showing.
@MainActor
final class FakeMenuNotifier: MenuNotifier {
    /// The Tracks that got a notification, in order.
    private(set) var notified: [Track] = []
    /// Each "Flip the record" notification posted, by the Record's last
    /// Track (nil when none was identified).
    private(set) var flips: [Track?] = []
    /// How many times First Press Menu removed the Flip notification itself.
    private(set) var flipRemovals = 0
    /// A Flip notification is posted and First Press Menu hasn't removed it.
    private(set) var isFlipShowing = false

    func notify(newTrack track: Track) { notified.append(track) }

    func notifyFlip(lastTrack: Track?) {
        flips.append(lastTrack)
        isFlipShowing = true
    }

    func removeFlip() {
        flipRemovals += 1
        isFlipShowing = false
    }
}
