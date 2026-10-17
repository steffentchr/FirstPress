import Foundation
import Network
import FirstPressMenuCore

/// Production MenuLink: browses Bonjour for `_firstpress._tcp` and opens a
/// WebSocket over Network.framework to the first First Press it finds
/// (ADR-0004). Choosing among several iPhones is out of scope.
///
/// It only moves messages; when to retry is First Press Menu's model's call.
@MainActor
final class BonjourMenuLink: MenuLink {
    private var handler: (@MainActor (MenuLinkEvent) -> Void)?
    private var browser: NWBrowser?
    private var connection: NWConnection?

    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void) {
        self.handler = handler
    }

    func connect() {
        // Already looking, or already linked.
        guard browser == nil, connection == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: MenuNetwork.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            MainActor.assumeIsolated {
                guard let first = results.first else { return }
                self.open(first.endpoint)
            }
        }
        browser.stateUpdateHandler = { state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated {
                self.stopBrowsing()
                self.handler?(.disconnected)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func send(_ message: Data) {
        guard let connection else { return }
        MenuNetwork.send(message, on: connection)
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func open(_ endpoint: NWEndpoint) {
        guard connection == nil else { return }
        stopBrowsing()
        let connection = NWConnection(to: endpoint, using: MenuNetwork.webSocketParameters())
        connection.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                guard self.connection === connection else { return }
                switch state {
                case .ready:
                    self.handler?(.connected)
                    self.receive(on: connection)
                case .failed, .cancelled, .waiting:
                    self.drop()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { data, context, _, error in
            MainActor.assumeIsolated {
                guard self.connection === connection else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if error != nil || metadata?.opcode == .close {
                    self.drop()
                    return
                }
                if let data, !data.isEmpty {
                    self.handler?(.received(data))
                }
                self.receive(on: connection)
            }
        }
    }

    private func drop() {
        guard let connection else { return }
        self.connection = nil
        connection.cancel()
        handler?(.disconnected)
    }
}
