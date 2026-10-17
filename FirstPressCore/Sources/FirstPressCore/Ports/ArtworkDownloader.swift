import Foundation

/// Port: fetches a Track's cover from its artwork URL, so History can show it
/// from the phone. Production: URLSession.
@MainActor
public protocol ArtworkDownloader: AnyObject {
    func download(_ url: URL) async throws -> Data
}
