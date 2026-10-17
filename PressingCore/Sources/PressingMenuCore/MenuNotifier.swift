import PressingCore

/// Port: posts Pressing Menu's Mac notifications. Production: the user
/// notification centre. A new Track's notification has the title as the
/// heading, the artist (and the album) below, and the cover attached once
/// its artwork loads.
///
/// A Flip's notification, "Flip the record", names the Record's last Track
/// if one was identified, and stays until the listener dismisses it or
/// Pressing Menu removes it.
///
/// Pressing Menu's model decides when to post and when to remove; this only
/// does it.
@MainActor
public protocol MenuNotifier: AnyObject {
    func notify(newTrack track: Track)
    /// "Flip the record": the side ran out during a Session.
    func notifyFlip(lastTrack: Track?)
    /// Removes the Flip notification: music started again.
    func removeFlip()
}
