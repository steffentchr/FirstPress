import Foundation

/// One HTTP client of the stream, such as a Sonos Room.
public struct StreamClientID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public enum StreamSinkEvent: Sendable, Equatable {
    /// A client asked for the stream. `wantsMetadata` is true when it sent `Icy-MetaData: 1`.
    case connected(StreamClientID, path: String, wantsMetadata: Bool)
    case disconnected(StreamClientID)
}

/// Port: where framed stream bytes go. The core does the ICY framing and
/// pre-roll per client. Production: an in-app HTTP server on a
/// Network.framework listener.
@MainActor
public protocol StreamSink: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (StreamSinkEvent) -> Void)
    func startListening(port: UInt16) throws
    func stopListening()
    /// Sends response headers to a client that just connected.
    func sendHeaders(_ headers: [String: String], to client: StreamClientID)
    func send(_ bytes: Data, to client: StreamClientID)
    func close(_ client: StreamClientID)
}
