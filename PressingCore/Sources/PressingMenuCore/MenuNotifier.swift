import PressingCore

/// Port: posts Pressing Menu's Mac notifications. Production: the user
/// notification centre. A new Track's notification has the title as the
/// heading, the artist (and the album) below, and the cover attached once
/// its artwork loads.
///
/// Pressing Menu's model decides which Tracks get one; this only posts it.
@MainActor
public protocol MenuNotifier: AnyObject {
    func notify(newTrack track: Track)
}
