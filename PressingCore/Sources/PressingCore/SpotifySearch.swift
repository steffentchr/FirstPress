import Foundation

extension Track {
    /// A Spotify search for this Track's artist and title. It opens the
    /// Spotify app when it's installed and the web otherwise.
    public var spotifySearchURL: URL {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? ""
        // Only unreserved characters follow a fixed prefix, so this always parses.
        return URL(string: "https://open.spotify.com/search/\(query)")!
    }

    /// RFC 3986 unreserved characters: everything else is percent-encoded,
    /// so a slash or a question mark in a title stays part of the search.
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
