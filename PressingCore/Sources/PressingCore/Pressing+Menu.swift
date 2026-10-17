import Foundation

/// Pressing Menus on Macs on the same network: each gets a snapshot when it
/// connects, and every one connected gets a new snapshot whenever what it
/// shows changes. Level meter updates never send one.
extension Pressing {
    func startMenuServer() {
        menuServer.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        menuServer.start()
    }

    private func handle(_ event: MenuServerEvent) {
        switch event {
        case .connected(let client):
            menuClients.insert(client)
            let snapshot = menuSnapshot
            lastMenuSnapshot = snapshot
            menuServer.send(MenuWire.encode(snapshot), to: client)
        case .received:
            break
        case .disconnected(let client):
            menuClients.remove(client)
        }
    }

    /// What Pressing Menus show now.
    var menuSnapshot: MenuSnapshot {
        let page: MenuSnapshot.Page = switch state.page {
        case .chooseInput: .chooseInput
        case .waiting: .waiting
        case .nowPlaying: .nowPlaying
        }
        let record: MenuSnapshot.Record? = switch state.session {
        case .idle: nil
        case .running(_, .playing): .playing
        case .running(_, .gap): .gap
        case .running(_, .flipped): .flipped
        }
        return MenuSnapshot(page: page, record: record, track: state.play?.track)
    }

    /// Called whenever `state` or `history` changes: sends a snapshot to every
    /// Pressing Menu if, and only if, it differs from the last one sent.
    func menuMayHaveChanged() {
        guard !menuClients.isEmpty else { return }
        let snapshot = menuSnapshot
        guard snapshot != lastMenuSnapshot else { return }
        lastMenuSnapshot = snapshot
        let message = MenuWire.encode(snapshot)
        for client in menuClients { menuServer.send(message, to: client) }
    }
}
