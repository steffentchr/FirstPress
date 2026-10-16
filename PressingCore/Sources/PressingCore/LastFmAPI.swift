import CryptoKit
import Foundation

/// Last.fm's web service, as Pressing uses it: builds, signs and sends
/// requests, and reads the JSON answers.
@MainActor
struct LastFmAPI {
    /// Why a call didn't come back with an answer.
    enum Failure: Error, Equatable {
        /// No answer worth reading: no network, or an HTTP error with no
        /// Last.fm error in the body. Worth trying again.
        case unreachable
        /// Last.fm answered with this error code.
        case lastFm(Int)

        /// Last.fm says to try again later: service offline (11), temporarily
        /// unavailable (16), operation failed (8) or rate limit exceeded (29).
        var isTransient: Bool {
            switch self {
            case .unreachable: true
            case .lastFm(let code): [8, 11, 16, 29].contains(code)
            }
        }

        /// The session key is no longer valid (9): sign in again.
        var isSessionInvalid: Bool { self == .lastFm(9) }

        /// Pressing's own API key or signature is refused: authentication
        /// failed (4), invalid API key (10), invalid signature (13) or
        /// suspended API key (26).
        var isMisconfigured: Bool {
            if case .lastFm(let code) = self { return [4, 10, 13, 26].contains(code) }
            return false
        }
    }

    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    /// The browser page where the listener approves Pressing.
    static let authPage = URL(string: "https://www.last.fm/api/auth/")!
    /// Where Last.fm sends the browser back to once the listener approves.
    static let callbackScheme = "pressing"
    static let callback = "pressing://lastfm-auth"

    let account: LastFmAccount
    let http: any LastFmHTTP

    /// A signed write (or `auth.*`) call: POST, every parameter in the body.
    func post(_ method: String, _ params: [String: String]) async throws(Failure) -> [String: Any] {
        var params = params.mapValues(Self.normalised)
        params["method"] = method
        params["api_key"] = account.apiKey
        params["api_sig"] = Self.signature(params, secret: account.secret)
        params["format"] = "json"
        let request = HTTPRequest(
            method: "POST",
            url: Self.endpoint,
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"],
            body: Data(Self.formEncoded(params).utf8)
        )
        return try await send(request)
    }

    /// An unsigned read: GET with the parameters in the query.
    func get(_ method: String, _ params: [String: String]) async throws(Failure) -> [String: Any] {
        var params = params.mapValues(Self.normalised)
        params["method"] = method
        params["api_key"] = account.apiKey
        params["format"] = "json"
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = Self.formEncoded(params)
        return try await send(HTTPRequest(method: "GET", url: components.url!))
    }

    /// Last.fm can answer 200 with an error in the body, or an HTTP error with
    /// a Last.fm error in the body; the body decides.
    private func send(_ request: HTTPRequest) async throws(Failure) -> [String: Any] {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw .unreachable
        }
        let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        if let code = json.flatMap({ Self.int($0["error"]) }) {
            throw .lastFm(code)
        }
        guard let json, (200..<300).contains(response.status) else { throw .unreachable }
        return json
    }

    /// The URL of the sign-in page for this token.
    func authPage(token: String) -> URL {
        var components = URLComponents(url: Self.authPage, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: account.apiKey),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "cb", value: Self.callback),
        ]
        return components.url!
    }

    // MARK: - Signing and encoding

    /// `api_sig`: every parameter but `format` and `callback`, sorted by name
    /// in byte order (so `artist[10]` comes before `artist[1]`), each name then
    /// its raw value, the secret appended; the md5 in lowercase hex.
    static func signature(_ params: [String: String], secret: String) -> String {
        let signed = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            .map { $0.key + $0.value }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(signed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Precomposed, so the bytes signed are the bytes sent whatever form the
    /// recogniser returned accented letters in.
    static func normalised(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    /// `name=value&…`, everything outside the unreserved set percent-encoded,
    /// so a `+`, `&` or `=` in a title survives.
    static func formEncoded(_ params: [String: String]) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
    }

    private static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    // MARK: - Reading answers

    /// Last.fm's JSON sends numbers as numbers or as strings.
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    /// A list Last.fm sends as an object when it has one item.
    static func list(_ value: Any?) -> [[String: Any]]? {
        switch value {
        case let array as [[String: Any]]: array
        case let object as [String: Any]: [object]
        default: nil
        }
    }
}
