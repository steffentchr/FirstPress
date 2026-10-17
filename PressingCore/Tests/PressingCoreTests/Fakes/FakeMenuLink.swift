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
    /// The phone is found but refuses the connection, so Pressing Menu's
    /// attempt fails at once.
    var refusesConnections = false
    /// Every message the phone sent, per Pressing Menu.
    private(set) var sent: [MenuConnectionID: [Data]] = [:]
    private var links: [MenuConnectionID: FakeMenuLink] = [:]
    /// Pressing Menus looking for the phone while it isn't advertised.
    private var looking: [FakeMenuLink] = []
    private var nextID = 1
    private var handler: (@MainActor (MenuServerEvent) -> Void)?

    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void) { self.handler = handler }
    func start() {
        isAdvertising = true
        let found = looking
        looking = []
        for link in found { link.phoneFound() }
    }

    func stop() {
        isAdvertising = false
        for link in Array(links.values) { link.drop() }
    }

    func send(_ message: Data, to connection: MenuConnectionID) {
        sent[connection, default: []].append(message)
        links[connection]?.deliver(message)
    }

    /// How many messages went to every Pressing Menu, all told.
    var sentCount: Int { sent.values.map(\.count).reduce(0, +) }

    // The network's side.

    /// A Pressing Menu looks for the phone: it connects at once while the
    /// phone is advertised, and as soon as it is otherwise.
    func accept(_ link: FakeMenuLink) -> MenuConnectionID? {
        guard isAdvertising else {
            if !looking.contains(where: { $0 === link }) { looking.append(link) }
            return nil
        }
        let id = MenuConnectionID(nextID)
        nextID += 1
        links[id] = link
        return id
    }

    func announce(_ connection: MenuConnectionID) { handler?(.connected(connection)) }

    /// Every message the phone received from any Pressing Menu, in order.
    private(set) var received: [Data] = []

    func receive(_ message: Data, from connection: MenuConnectionID) {
        received.append(message)
        handler?(.received(message, from: connection))
    }

    func forget(_ connection: MenuConnectionID) {
        guard links.removeValue(forKey: connection) != nil else { return }
        handler?(.disconnected(connection))
    }
}

/// One Mac's end: the MenuLink port Pressing Menu is wired to.
@MainActor
final class FakeMenuLink: MenuLink {
    let server: FakeMenuServer
    private(set) var connectAttempts = 0
    private(set) var connection: MenuConnectionID?
    private var handler: (@MainActor (MenuLinkEvent) -> Void)?

    init(server: FakeMenuServer) { self.server = server }

    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void) { self.handler = handler }

    func connect() {
        connectAttempts += 1
        phoneFound()
    }

    /// The phone is advertised: connect to it, unless connected already.
    func phoneFound() {
        guard connection == nil else { return }
        if server.refusesConnections && server.isAdvertising {
            handler?(.disconnected)
            return
        }
        guard let id = server.accept(self) else { return }
        connection = id
        handler?(.connected)
        server.announce(id)
    }

    func send(_ message: Data) {
        guard let connection else { return }
        server.receive(message, from: connection)
    }

    var isConnected: Bool { connection != nil }

    /// A message as the phone would send it, raw.
    func deliver(_ message: Data) { handler?(.received(message)) }
    func deliver(json: String) { deliver(Data(json.utf8)) }

    /// The link goes down: Wi-Fi dropped, or the phone went to sleep.
    func drop() {
        guard let id = connection else { return }
        connection = nil
        server.forget(id)
        handler?(.disconnected)
    }
}
