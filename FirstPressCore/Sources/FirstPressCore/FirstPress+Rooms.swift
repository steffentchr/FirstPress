import Foundation

/// Room discovery and the listener's Room choices.
extension FirstPress {
    /// Intent from the Rooms sheet: switch a Room on or off in First Press.
    public func switchRoom(_ id: RoomState.ID, on: Bool) {
        updateChoice(for: id) { $0.isOn = on }
        roomSwitched(id, on: on)
    }

    /// Intent from the Rooms sheet: the volume First Press plays this Room at.
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
            setReachable(true, host: device.host)
            // Any one player knows the whole household (ADR-0003). Bonjour
            // reports players in a burst; one read covers the burst, and
            // players found later read it again to pick up new Rooms.
            guard !isReadingTopology else { return }
            isReadingTopology = true
            Task {
                await readTopology(from: device.host)
                isReadingTopology = false
                recoverRoomsAtLaunch()
                // Rooms found or back during a Session join it.
                takeOverMissingRooms()
            }
        case .lost(let device):
            // The topology from the next player found replaces the list.
            setReachable(false, host: device.host)
            roomLost(at: device.host)
        }
    }

    private func readTopology(from host: String) async {
        let request = SOAP.request(host: host, .zoneGroupTopology, "GetZoneGroupState", [:])
        guard let response = try? await sonos.send(request),
              let xml = try? SOAP.outArguments(of: response)["ZoneGroupState"]
        else { return }
        applyTopology(ZoneGroupState.rooms(in: xml))
    }

    /// Lists the household's Rooms, keeping what First Press knows about each.
    func applyTopology(_ rooms: [TopologyRoom]) {
        hold.topology = rooms
        roomHosts = Dictionary(rooms.map { ($0.id, $0.host) }, uniquingKeysWith: { first, _ in first })
        let known = Dictionary(state.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        state.rooms = rooms
            .map { room in
                let choice = settings.rooms[room.id] ?? .default
                var state = RoomState(id: room.id, name: room.name, isOn: choice.isOn, volume: choice.volume)
                state.isReachable = known[room.id]?.isReachable ?? true
                state.isSteppedBack = known[room.id]?.isSteppedBack ?? false
                return state
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func updateChoice(for id: RoomState.ID, _ change: (inout RoomChoice) -> Void) {
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
