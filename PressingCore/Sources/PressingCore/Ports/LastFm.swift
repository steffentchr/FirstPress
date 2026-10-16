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
    /// Opens `url` and returns the callback URL Last.fm redirects to. Throws
    /// when the listener closes the sheet without a redirect.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// Port: where credentials are kept. Production: the iOS Keychain.
@MainActor
public protocol Keychain: AnyObject {
    func loadLastFmSession() -> LastFmSession?
    func saveLastFmSession(_ session: LastFmSession)
    func deleteLastFmSession()
}

/// Pressing's Last.fm API account: build configuration, never committed.
public struct LastFmAccount: Sendable, Equatable {
    public var apiKey: String
    public var secret: String

    public init(apiKey: String, secret: String) {
        self.apiKey = apiKey
        self.secret = secret
    }
}

/// The listener's Last.fm session: whose it is, and the key that signs their
/// scrobbles. Session keys don't expire until the listener revokes them.
public struct LastFmSession: Sendable, Equatable, Codable {
    public var username: String
    public var key: String

    public init(username: String, key: String) {
        self.username = username
        self.key = key
    }
}

/// Everything Pressing needs to reach Last.fm.
public struct LastFmPorts {
    /// Nil when the build has no API key and secret: Last.fm can't be connected.
    public var account: LastFmAccount?
    public var http: any LastFmHTTP
    public var webAuth: any WebAuth
    public var keychain: any Keychain

    public init(account: LastFmAccount?, http: any LastFmHTTP, webAuth: any WebAuth, keychain: any Keychain) {
        self.account = account
        self.http = http
        self.webAuth = webAuth
        self.keychain = keychain
    }
}
