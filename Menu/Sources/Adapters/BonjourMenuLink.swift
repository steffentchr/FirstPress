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
                guard self.browser === browser, let first = results.first else { return }
                self.open(first.endpoint)
            }
        }
        browser.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                guard self.browser === browser else { return }
                switch state {
                case .waiting(let error) where Self.isLocalNetworkDenied(error):
                    // The browser waits, and goes on by itself once macOS
                    // allows First Press Menu on the local network.
                    self.handler?(.localNetworkDenied)
                case .failed, .cancelled:
                    // Never left stuck: First Press Menu's model calls
                    // connect() again, which starts a new browser.
                    self.stopBrowsing()
                    self.handler?(.disconnected)
                default:
                    break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Bonjour's answer when macOS hasn't allowed First Press Menu on the
    /// local network (System Settings › Privacy & Security › Local Network).
    nonisolated private static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        guard case .dns(let code) = error else { return false }
        return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
            || code == DNSServiceErrorType(kDNSServiceErr_NoAuth)
    }

    func send(_ message: Data) {
        guard let connection else { return }
        MenuNetwork.send(message, on: connection)
    }

    private func stopBrowsing() {
        let browser = self.browser
        self.browser = nil
        browser?.cancel()
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
                case .waiting(let error):
                    if Self.isLocalNetworkDenied(error) || connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        self.handler?(.localNetworkDenied)
                    }
                    self.drop()
                case .failed, .cancelled:
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
