import Foundation

/// One occurrence of a Track during a Record. History is the list of Plays.
///
/// Kept on the phone from the moment it starts, and saved again whenever it
/// changes: when it ends, and as its scrobble status moves on.
public struct Play: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    /// Artist, title, album when known, and the artwork URL. The cover itself
    /// is kept on the phone by that URL; see `Pressing.cover(for:)`.
    public var track: Track
    /// The latest of: the start worked back from the match, the start of the
    /// Record, and the end of the previous Play.
    public var startedAt: Date
    /// When the Play ended, nil while it is the current one.
    public var endedAt: Date?
    /// Whether the Play reached Last.fm.
    public var scrobble: ScrobbleStatus

    public init(id: UUID = UUID(), track: Track, startedAt: Date, endedAt: Date? = nil, scrobble: ScrobbleStatus = .notScrobbled) {
        self.id = id
        self.track = track
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.scrobble = scrobble
    }

    // Plays saved before a field existed decode with that field's default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        track = try container.decode(Track.self, forKey: .track)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        scrobble = try container.decodeIfPresent(ScrobbleStatus.self, forKey: .scrobble) ?? .notScrobbled
    }
}

/// Whether a Play reached Last.fm.
public enum ScrobbleStatus: String, Sendable, Hashable, Codable {
    /// Made while Last.fm was connected and not settled yet: still playing
    /// towards qualifying, or qualified and queued for Last.fm.
    case pending
    /// Last.fm accepted it.
    case scrobbled
    /// Last.fm refused it.
    case rejected
    /// It ended before it qualified (too short, or not played long enough).
    case notEligible
    /// Last.fm wasn't connected when it played. It is never sent later.
    case notScrobbled
}

extension Track {
    /// The same Track, whatever the cover or album: artist and title alike,
    /// ignoring case and accents.
    func isSame(as other: Track) -> Bool {
        Self.key(artist, title) == Self.key(other.artist, other.title)
    }

    private static func key(_ artist: String, _ title: String) -> String {
        "\(artist)\u{1F}\(title)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
