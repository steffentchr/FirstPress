import Foundation
import PressingCore

// Fakes for the ports later tickets wire into Pressing. Each records what the
// core asked of the outside world, and lets a test play the outside world back.

/// Sonos at the HTTP level: the test answers each request by URL path.
@MainActor
final class FakeSonosNetwork: SonosNetwork {
    private(set) var requests: [HTTPRequest] = []
    private(set) var isDiscovering = false
    var respond: @MainActor (HTTPRequest) throws -> HTTPResponse = { _ in HTTPResponse(status: 200) }
    private var handler: (@MainActor (SonosDiscoveryEvent) -> Void)?

    func setDiscoveryHandler(_ handler: @escaping @MainActor (SonosDiscoveryEvent) -> Void) { self.handler = handler }
    func startDiscovery() { isDiscovering = true }
    func stopDiscovery() { isDiscovering = false }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try respond(request)
    }

    func discover(_ event: SonosDiscoveryEvent) { handler?(event) }
}

@MainActor
final class FakeRecognizer: Recognizer {
    private(set) var searches = 0
    /// Answers in order; `.noMatch` once they run out.
    var answers: [Recognition] = []

    func recognize(_ samples: [Float], sampleRate: Double) async throws -> Recognition {
        searches += 1
        return answers.isEmpty ? .noMatch : answers.removeFirst()
    }
}

@MainActor
final class FakeLastFmHTTP: LastFmHTTP {
    private(set) var requests: [HTTPRequest] = []
    var respond: @MainActor (HTTPRequest) throws -> HTTPResponse = { _ in HTTPResponse(status: 200) }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try respond(request)
    }
}

@MainActor
final class FakeWebAuth: WebAuth {
    private(set) var openedURLs: [URL] = []
    var callback: URL?

    struct Cancelled: Error {}

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURLs.append(url)
        guard let callback else { throw Cancelled() }
        return callback
    }
}

/// A Scheduler the test moves forward by hand.
@MainActor
final class FakeScheduler: Scheduler {
    private final class Work: ScheduledWork {
        let due: Date
        let action: @MainActor () -> Void
        var cancelled = false
        init(due: Date, action: @escaping @MainActor () -> Void) {
            self.due = due
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private(set) var now: Date
    private var pending: [Work] = []

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = Work(due: now.addingTimeInterval(delay), action: work)
        pending.append(item)
        return item
    }

    /// Moves time forward, firing due work in order.
    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = pending.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            pending.removeAll { $0 === next }
            now = next.due
            next.action()
        }
        pending.removeAll { $0.cancelled }
        now = end
    }
}

/// Collects what the core writes to each stream client.
@MainActor
final class FakeStreamSink: StreamSink {
    private(set) var listeningPort: UInt16?
    /// The phone's address on the LAN.
    var localAddress: String? = "192.168.1.50"
    private(set) var headers: [StreamClientID: [String: String]] = [:]
    private(set) var received: [StreamClientID: Data] = [:]
    private(set) var closed: Set<StreamClientID> = []
    private var handler: (@MainActor (StreamSinkEvent) -> Void)?

    func setEventHandler(_ handler: @escaping @MainActor (StreamSinkEvent) -> Void) { self.handler = handler }
    func startListening(port: UInt16) throws { listeningPort = port }
    func stopListening() { listeningPort = nil }
    func sendHeaders(_ headers: [String: String], to client: StreamClientID) { self.headers[client] = headers }
    func send(_ bytes: Data, to client: StreamClientID) { received[client, default: Data()].append(bytes) }
    func close(_ client: StreamClientID) { closed.insert(client) }

    func connect(_ client: StreamClientID, path: String, wantsMetadata: Bool) {
        handler?(.connected(client, path: path, wantsMetadata: wantsMetadata))
    }

    func disconnect(_ client: StreamClientID) {
        handler?(.disconnected(client))
    }
}
