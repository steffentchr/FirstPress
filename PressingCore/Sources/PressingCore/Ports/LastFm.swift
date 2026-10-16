import Foundation

/// Port: sends Last.fm API requests. The core builds and signs them (`api_sig`).
/// Production: URLSession.
@MainActor
public protocol LastFmHTTP: AnyObject {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Port: the browser sign-in at last.fm/api/auth, so Pressing never sees the
/// listener's password. Production: `ASWebAuthenticationSession`.
@MainActor
public protocol WebAuth: AnyObject {
    /// Opens `url` and returns the callback URL Last.fm redirects to.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}
