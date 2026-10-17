import Foundation
import PressingCore
import PressingMenuCore

// The home network between the phone and Pressing Menus, in memory. A
// FakeMenuLink is one Mac's end; the FakeMenuServer is the phone's. Messages
// are delivered at once, in order, as the real WebSocket delivers them.

/// The phone's end: the MenuServer port Pressing is wired to.
@MainActor
final class FakeMenuServer: MenuServer {
    private(set) var isAdvertising = false
    /// Every message the phone sent, per Pressing Menu.
    private(set) var sent: [MenuClientID: [Data]] = [:]
    private var links: [MenuClientID: FakeMenuLink] = [:]
    private var nextID = 1
    private var handler: (@MainActor (MenuServerEvent) -> Void)?

    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void) { self.handler = handler }
    func start() { isAdvertising = true }

    func stop() {
        isAdvertising = false
        for link in Array(links.values) { link.drop() }
    }

    func send(_ message: Data, to client: MenuClientID) {
        sent[client, default: []].append(message)
        links[client]?.deliver(message)
    }

    /// How many messages went to every Pressing Menu, all told.
    var sentCount: Int { sent.values.map(\.count).reduce(0, +) }

    // The network's side.

    func accept(_ link: FakeMenuLink) -> MenuClientID? {
        guard isAdvertising else { return nil }
        let id = MenuClientID(nextID)
        nextID += 1
        links[id] = link
        return id
    }

    func announce(_ client: MenuClientID) { handler?(.connected(client)) }

    func receive(_ message: Data, from client: MenuClientID) { handler?(.received(message, from: client)) }

    func forget(_ client: MenuClientID) {
        guard links.removeValue(forKey: client) != nil else { return }
        handler?(.disconnected(client))
    }
}

/// One Mac's end: the MenuLink port Pressing Menu is wired to.
@MainActor
final class FakeMenuLink: MenuLink {
    let server: FakeMenuServer
    private(set) var connectAttempts = 0
    private(set) var client: MenuClientID?
    private var handler: (@MainActor (MenuLinkEvent) -> Void)?

    init(server: FakeMenuServer) { self.server = server }

    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void) { self.handler = handler }

    func connect() {
        connectAttempts += 1
        guard client == nil else { return }
        guard let id = server.accept(self) else {
            handler?(.disconnected)
            return
        }
        client = id
        handler?(.connected)
        server.announce(id)
    }

    func send(_ message: Data) {
        guard let client else { return }
        server.receive(message, from: client)
    }

    var isConnected: Bool { client != nil }

    /// A message as the phone would send it, raw.
    func deliver(_ message: Data) { handler?(.received(message)) }
    func deliver(json: String) { deliver(Data(json.utf8)) }

    /// The link goes down: Wi-Fi dropped, or the phone went to sleep.
    func drop() {
        guard let id = client else { return }
        client = nil
        server.forget(id)
        handler?(.disconnected)
    }
}
