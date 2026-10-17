import Foundation

/// A song as identified: artist, title, album and cover.
public struct Track: Sendable, Hashable, Codable {
    public var artist: String
    public var title: String
    public var album: String?
    public var artworkURL: URL?

    public init(artist: String, title: String, album: String? = nil, artworkURL: URL? = nil) {
        self.artist = artist
        self.title = title
        self.album = album
        self.artworkURL = artworkURL
    }
}

public enum Recognition: Sendable, Equatable {
    /// The Track, and how far into it the searched audio started.
    case match(Track, offset: TimeInterval)
    case noMatch
}

/// Port: identifies a Track from mono audio. Production: ShazamKit, with a
/// fresh `SHSession` per search.
@MainActor
public protocol Recognizer: AnyObject {
    func recognize(_ samples: [Float], sampleRate: Double) async throws -> Recognition
}
