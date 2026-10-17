import PressingCore

/// Port: posts the Mac notification for a new Track. Production: the user
/// notification centre, with the title as the heading, the artist (and the
/// album) below, and the cover attached once its artwork loads.
///
/// Pressing Menu's model decides which Tracks get one; this only posts it.
@MainActor
public protocol TrackNotifier: AnyObject {
    func notify(newTrack track: Track)
}
