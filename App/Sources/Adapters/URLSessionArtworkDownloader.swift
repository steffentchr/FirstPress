import Foundation
import PressingCore

/// Production ArtworkDownloader: a plain GET.
@MainActor
final class URLSessionArtworkDownloader: ArtworkDownloader {
    struct BadResponse: Error {
        var status: Int
    }

    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BadResponse(status: http.statusCode)
        }
        return data
    }
}
