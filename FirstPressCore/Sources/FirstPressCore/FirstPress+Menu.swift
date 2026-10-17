import Foundation

/// First Press Menus on Macs on the same network: each gets a snapshot when it
/// connects, and every one connected gets a new snapshot whenever what it
/// shows changes. Level meter updates never send one.
extension FirstPress {
    func startMenuServer() {
        menuServer.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        menuServer.start()
    }

    private func handle(_ event: MenuServerEvent) {
        switch event {
        case .connected(let connection):
            menuConnections.insert(connection)
            let snapshot = menuSnapshot
            lastMenuSnapshot = snapshot
            menuServer.send(MenuWire.encode(snapshot), to: connection)
        case .received(let message, _):
            guard let command = MenuWire.decodeCommand(message) else { return }
            perform(command)
        case .disconnected(let connection):
            menuConnections.remove(connection)
        }
    }

    /// A command from a First Press Menu is the phone's own intent, but not a
    /// touch: the screen is left as it is. One for a Room the phone doesn't
    /// know is ignored.
    private func perform(_ command: MenuCommand) {
        switch command {
        case .switchRoom(let id, let on):
            guard state.rooms.contains(where: { $0.id == id }) else { return }
            switchRoom(id, on: on)
        case .setVolume(let id, let volume):
            guard state.rooms.contains(where: { $0.id == id }) else { return }
            setVolume(volume, for: id)
        case .switchPhoneOutput(let on):
            switchPhoneOutput(on: on)
        }
    }

    /// What First Press Menus show now.
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
        let recent = Self.recentPlays(in: history, excluding: state.play?.id, limit: MenuSnapshot.panelHistoryLimit)
        return MenuSnapshot(
            page: page,
            record: record,
            track: state.play?.track,
            recentPlays: recent.map { MenuSnapshot.Play(track: $0.track, startedAt: $0.startedAt) },
            rooms: state.rooms.map {
                MenuSnapshot.Room(id: $0.id, name: $0.name, isOn: $0.isOn, volume: $0.volume, isReachable: $0.isReachable, isSteppedBack: $0.isSteppedBack)
            },
            phoneOutput: MenuSnapshot.PhoneOutput(isOn: state.phoneOutput.isOn, route: state.phoneOutput.route),
            lastTrack: record == .flipped ? sessionLastTrack : nil
        )
    }

    /// Called whenever `state` or `history` changes: sends a snapshot to every
    /// First Press Menu if, and only if, it differs from the last one sent.
    func menuMayHaveChanged() {
        guard !menuConnections.isEmpty else { return }
        let snapshot = menuSnapshot
        guard snapshot != lastMenuSnapshot else { return }
        lastMenuSnapshot = snapshot
        let message = MenuWire.encode(snapshot)
        for connection in menuConnections { menuServer.send(message, to: connection) }
    }
}
