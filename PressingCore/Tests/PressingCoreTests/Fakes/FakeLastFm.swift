import Foundation
import PressingCore

/// One Last.fm API call as the core sent it: the HTTP method and every
/// parameter, decoded from the query (GET) or the form body (POST).
struct LastFmCall: CustomStringConvertible {
    var httpMethod: String
    var params: [String: String]
    /// The raw form body or query, as sent.
    var encoded: String

    var method: String { params["method"] ?? "" }
    var description: String { "\(httpMethod) \(method) \(params)" }

    init(_ request: HTTPRequest) {
        httpMethod = request.method
        if request.method == "GET" {
            encoded = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        } else {
            encoded = String(decoding: request.body, as: UTF8.self)
        }
        var params: [String: String] = [:]
        for pair in encoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
            params[name] = value
        }
        self.params = params
    }

    /// The scrobbles in a `track.scrobble` batch, in index order.
    var scrobbles: [(artist: String, track: String, album: String?, timestamp: String)] {
        var items: [(String, String, String?, String)] = []
        var index = 0
        while let artist = params["artist[\(index)]"] {
            items.append((artist, params["track[\(index)]"] ?? "", params["album[\(index)]"], params["timestamp[\(index)]"] ?? ""))
            index += 1
        }
        return items
    }
}

/// Last.fm at the HTTP level. Answers each call by its `method` parameter;
/// a test replaces an answer to play Last.fm back differently.
@MainActor
final class FakeLastFm: LastFmHTTP {
    struct Offline: Error {}

    /// Every request, in order.
    private(set) var requests: [HTTPRequest] = []
    var calls: [LastFmCall] { requests.map(LastFmCall.init) }
    func calls(_ method: String) -> [LastFmCall] { calls.filter { $0.method == method } }

    /// When true, every request fails as it does with no network.
    var isOffline = false
    /// Answers by method. A method with no answer gets error 3 (invalid method).
    var answers: [String: @MainActor (LastFmCall) -> HTTPResponse] = [:]

    init() {
        answers["auth.getToken"] = { _ in .json(#"{"token":"TOKEN"}"#) }
        answers["auth.getSession"] = { _ in .json(#"{"session":{"name":"listener","key":"SESSIONKEY","subscriber":0}}"#) }
        answers["track.updateNowPlaying"] = { _ in .json(##"{"nowplaying":{"ignoredMessage":{"code":"0","#text":""}}}"##) }
        answers["track.getInfo"] = { _ in .lastFmError(6, "Track not found") }
        answers["track.scrobble"] = Self.acceptingEveryPlay
    }

    /// Last.fm's usual answer to `track.scrobble`: every Play in the batch accepted.
    static let acceptingEveryPlay: @MainActor (LastFmCall) -> HTTPResponse = { call in
        .scrobbles(ignoredCodes: call.scrobbles.map { _ in 0 })
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if isOffline { throw Offline() }
        let call = LastFmCall(request)
        guard let answer = answers[call.method] else { return .lastFmError(3, "Invalid Method") }
        return answer(call)
    }

    /// Last.fm knows the Track: its length in milliseconds and its album.
    func knows(_ track: Track, durationMilliseconds: Int, album: String? = nil) {
        let previous = answers["track.getInfo"]
        answers["track.getInfo"] = { call in
            guard call.params["artist"] == track.artist, call.params["track"] == track.title else {
                return previous?(call) ?? .lastFmError(6, "Track not found")
            }
            let albumJSON = album.map { #","album":{"artist":"\#(track.artist)","title":"\#($0)"}"# } ?? ""
            return .json(#"{"track":{"name":"\#(track.title)","duration":"\#(durationMilliseconds)","artist":{"name":"\#(track.artist)"}\#(albumJSON)}}"#)
        }
    }
}

extension HTTPResponse {
    static func json(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    static func lastFmError(_ code: Int, _ message: String = "", status: Int = 200) -> HTTPResponse {
        .json(#"{"error":\#(code),"message":"\#(message)"}"#, status: status)
    }

    /// A `track.scrobble` answer: one item per scrobble with its
    /// `ignoredMessage` code (0 accepted). Last.fm sends a single item as an
    /// object rather than an array, and numbers as strings.
    static func scrobbles(ignoredCodes: [Int]) -> HTTPResponse {
        let items = ignoredCodes.map { code in
            ##"{"artist":{"corrected":"0","#text":"a"},"track":{"corrected":"0","#text":"t"},"timestamp":"0","ignoredMessage":{"code":"\##(code)","#text":""}}"##
        }
        let accepted = ignoredCodes.filter { $0 == 0 }.count
        let list = items.count == 1 ? items[0] : "[\(items.joined(separator: ","))]"
        return .json(#"{"scrobbles":{"@attr":{"accepted":\#(accepted),"ignored":\#(ignoredCodes.count - accepted)},"scrobble":\#(list)}}"#)
    }
}

/// The browser sign-in. By default the listener approves and Last.fm
/// redirects back to Pressing.
@MainActor
final class FakeWebAuth: WebAuth {
    struct Cancelled: Error {}

    private(set) var opened: [(url: URL, callbackScheme: String)] = []
    /// What the sheet returns; nil means the listener closed it.
    var callback: URL? = URL(string: "pressing://lastfm-auth?token=TOKEN")

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        opened.append((url, callbackScheme))
        guard let callback else { throw Cancelled() }
        return callback
    }
}

/// The Keychain, in memory. Share one between two cores to simulate a restart.
@MainActor
final class FakeKeychain: Keychain {
    var session: LastFmSession?

    init(session: LastFmSession? = nil) {
        self.session = session
    }

    func loadLastFmSession() -> LastFmSession? { session }
    func saveLastFmSession(_ session: LastFmSession) { self.session = session }
    func deleteLastFmSession() { session = nil }
}

extension LastFmAccount {
    static let test = LastFmAccount(apiKey: "0123456789abcdef0123456789abcdef", secret: "s3cr3t")
}

extension LastFmSession {
    static let listener = LastFmSession(username: "listener", key: "SESSIONKEY")
}
