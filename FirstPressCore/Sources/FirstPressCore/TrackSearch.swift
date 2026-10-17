import Foundation

extension Track {
    /// A Spotify search for this Track's artist and title. It opens the
    /// Spotify app when it's installed and the web otherwise.
    public var spotifySearchURL: URL {
        // Only unreserved characters follow a fixed prefix, so this always parses.
        URL(string: "https://open.spotify.com/search/\(searchQuery)")!
    }

    /// An Apple Music search for this Track's artist and title, for First Press
    /// Menu's "Find songs in" setting.
    public var appleMusicSearchURL: URL {
        // Only unreserved characters follow a fixed prefix, so this always parses.
        URL(string: "https://music.apple.com/search?term=\(searchQuery)")!
    }

    /// The artist and title, with everything but RFC 3986 unreserved
    /// characters percent-encoded, so a slash, an ampersand or a question
    /// mark in a title stays part of the search.
    private var searchQuery: String {
        "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? ""
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
