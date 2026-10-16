import Foundation

/// Room discovery and the listener's Room choices.
extension Pressing {
    /// Intent from the main screen: switch a Room on or off in Pressing.
    public func switchRoom(_ id: RoomState.ID, on: Bool) {
        updateChoice(for: id) { $0.isOn = on }
    }

    /// Intent from the main screen: the volume Pressing plays this Room at.
    public func setVolume(_ volume: Int, for id: RoomState.ID) {
        let volume = min(max(volume, 0), 100)
        updateChoice(for: id) { $0.volume = volume }
        roomVolumeChanged(id)
    }

    func startDiscovery() {
        sonos.setDiscoveryHandler { [weak self] event in
            self?.handle(event)
        }
        sonos.startDiscovery()
    }

    private func handle(_ event: SonosDiscoveryEvent) {
        switch event {
        case .found(let device):
            // Any one player knows the whole household (ADR-0003). Bonjour
            // reports players in a burst; one read covers the burst, and
            // players found later read it again to pick up new Rooms.
            guard !isReadingTopology else { return }
            isReadingTopology = true
            Task {
                await readTopology(from: device.host)
                isReadingTopology = false
            }
        case .lost:
            // The topology from the next player found replaces the list.
            break
        }
    }

    private func readTopology(from host: String) async {
        let request = SOAP.request(host: host, .zoneGroupTopology, "GetZoneGroupState", [:])
        guard let response = try? await sonos.send(request),
              let xml = try? SOAP.outArguments(of: response)["ZoneGroupState"]
        else { return }
        let rooms = ZoneGroupState.rooms(in: xml)
        roomHosts = Dictionary(rooms.map { ($0.id, $0.host) }, uniquingKeysWith: { first, _ in first })
        state.rooms = rooms
            .map { room in
                let choice = settings.rooms[room.id] ?? .default
                return RoomState(id: room.id, name: room.name, isOn: choice.isOn, volume: choice.volume)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateChoice(for id: RoomState.ID, _ change: (inout RoomChoice) -> Void) {
        var choice = settings.rooms[id] ?? .default
        change(&choice)
        settings.rooms[id] = choice
        store.saveSettings(settings)
        if let index = state.rooms.firstIndex(where: { $0.id == id }) {
            state.rooms[index].isOn = choice.isOn
            state.rooms[index].volume = choice.volume
        }
    }
}
