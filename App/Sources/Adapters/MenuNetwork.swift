import Foundation
import Network

/// The network both ends of the Pressing Menu link agree on (ADR-0004): the
/// Bonjour service type, and WebSocket over TCP carrying one JSON message
/// per text frame. Shared by the phone's BonjourMenuServer and Pressing
/// Menu's BonjourMenuLink; it imports only Foundation and Network.
enum MenuNetwork {
    /// The Bonjour service Pressing advertises and Pressing Menu browses.
    static let serviceType = "_pressing._tcp"

    /// TCP with WebSocket on top, answering pings by itself.
    static func webSocketParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        return parameters
    }

    /// Sends one message as a single WebSocket text frame.
    static func send(_ message: Data, on connection: NWConnection, completion: @escaping @Sendable (NWError?) -> Void = { _ in }) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "pressing", metadata: [metadata])
        connection.send(content: message, contentContext: context, isComplete: true, completion: .contentProcessed(completion))
    }
}
