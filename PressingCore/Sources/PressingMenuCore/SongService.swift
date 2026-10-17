import Foundation
import PressingCore

/// The "Find songs in" setting: where right-clicking a Track in the panel
/// searches for it.
public enum SongService: String, Sendable, CaseIterable {
    case spotify
    case appleMusic

    public static let `default` = SongService.spotify

    public func searchURL(for track: Track) -> URL {
        switch self {
        case .spotify: track.spotifySearchURL
        case .appleMusic: track.appleMusicSearchURL
        }
    }
}
