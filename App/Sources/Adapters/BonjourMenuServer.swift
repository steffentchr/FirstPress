import Foundation
import Network
import PressingCore

/// Production MenuServer: a WebSocket listener on Network.framework,
/// advertised over Bonjour as `_pressing._tcp` (ADR-0004).
///
/// It only moves messages: each WebSocket text message is one JSON message
/// the core built or will read. Several Pressing Menus may connect at once.
/// A listener that fails, for example after the app was suspended, is
/// started again after a short wait.
@MainActor
final class BonjourMenuServer: MenuServer {
    static let serviceType = "_pressing._tcp"

    private var listener: NWListener?
    private var isStarted = false
    private var handler: (@MainActor (MenuServerEvent) -> Void)?
    private var connections: [Int: NWConnection] = [:]
    private var nextID = 1

    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        isStarted = true
        listen()
    }

    func stop() {
        isStarted = false
        listener?.cancel()
        listener = nil
        for id in Array(connections.keys) { disconnect(id) }
    }

    func send(_ message: Data, to connection: MenuConnectionID) {
        guard let socket = connections[connection.rawValue] else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "pressing", metadata: [metadata])
        socket.send(content: message, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            MainActor.assumeIsolated {
                if error != nil { self.disconnect(connection.rawValue) }
            }
        })
    }

    // MARK: - Listener

    private func listen() {
        guard isStarted, listener == nil else { return }
        let parameters = NWParameters.tcp
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        guard let listener = try? NWListener(using: parameters) else {
            listenAgainSoon()
            return
        }
        // No name: Bonjour uses the phone's name.
        listener.service = NWListener.Service(type: Self.serviceType)
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { self.accept(connection) }
        }
        listener.stateUpdateHandler = { state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated {
                self.listener?.cancel()
                self.listener = nil
                self.listenAgainSoon()
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func listenAgainSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { self.listen() }
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = nextID
        nextID += 1
        connections[id] = connection
        connection.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    self.handler?(.connected(MenuConnectionID(id)))
                case .failed, .cancelled:
                    self.disconnect(id)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receive(id)
    }

    private func receive(_ id: Int) {
        guard let connection = connections[id] else { return }
        connection.receiveMessage { data, context, _, error in
            MainActor.assumeIsolated {
                guard self.connections[id] != nil else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if error != nil || metadata?.opcode == .close {
                    self.disconnect(id)
                    return
                }
                if let data, !data.isEmpty, metadata?.opcode == .text || metadata?.opcode == .binary {
                    self.handler?(.received(data, from: MenuConnectionID(id)))
                }
                self.receive(id)
            }
        }
    }

    private func disconnect(_ id: Int) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel()
        handler?(.disconnected(MenuConnectionID(id)))
    }
}
