import Foundation

/// One occurrence of a Track during a Record. History is the list of Plays.
public struct Play: Sendable, Equatable, Codable {
    public var track: Track
    /// When the Play started.
    public var startedAt: Date
    /// When the Play ended, nil while it is the current one.
    public var endedAt: Date?

    public init(track: Track, startedAt: Date, endedAt: Date? = nil) {
        self.track = track
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

extension Track {
    /// The same song, whatever the cover or album: artist and title alike,
    /// ignoring case and accents.
    func isSame(as other: Track) -> Bool {
        Self.key(artist, title) == Self.key(other.artist, other.title)
    }

    private static func key(_ artist: String, _ title: String) -> String {
        "\(artist)\u{1F}\(title)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
