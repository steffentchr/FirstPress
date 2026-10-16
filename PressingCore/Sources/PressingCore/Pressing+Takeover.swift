import Foundation

/// The Rooms Pressing holds in a Session.
///
/// One held Room leads: it plays the stream, and the others join its Sonos
/// group with `x-rincon:` so every Room plays in sync. Everything here is
/// changed only by work on the Sonos queue, in the order it was asked for.
struct Hold {
    /// Rooms Pressing plays in this Session, by RINCON id.
    var rooms: Set<String> = []
    /// The held Room that plays the stream.
    var leader: String?
    /// The household's groups as last read.
    var topology: [TopologyRoom] = []
    /// The volume each held Room last had at Sonos, as Pressing set or read it.
    var volumes: [String: Int] = [:]
    /// The next Session monitor read.
    var monitor: (any ScheduledWork)?
    /// A monitor read is queued or under way.
    var isPolling = false
}

/// Takeover at the start of a Session and Stop at its end.
extension Pressing {
    /// What Sonos shows as the station: SoCo's title-only radio DIDL-Lite.
    static let stationMetadata = #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="R:0/0/0" parentID="R:0/0" restricted="true"><dc:title>Pressing</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item></DIDL-Lite>"#

    /// Whether a Room's source is a Pressing stream, from this phone or from
    /// this phone at an earlier address: the port and path are fixed.
    static func isPressingStream(_ uri: String) -> Bool {
        guard let components = URLComponents(string: uri) else { return false }
        return components.scheme == "x-rincon-mp3radio"
            && components.port == Int(streamPort)
            && components.path == streamPath
    }

    /// Session start: takes over every switched-on Room.
    func takeOverRooms() {
        startMonitor()
        enqueueSonos { [weak self] in
            guard let self else { return }
            hold.rooms = []
            hold.leader = nil
            for index in state.rooms.indices { state.rooms[index].isSteppedBack = false }
            await takeOver(state.rooms.filter(\.isOn).map(\.id))
        }
    }

    /// Session end: Stop to the leader only. Its group stops with it; nothing
    /// is ungrouped and nothing restored.
    func stopRooms() {
        stopMonitor()
        enqueueSonos { [weak self] in
            guard let self else { return }
            if let leader = hold.leader, let host = roomHosts[leader] {
                try? await send(host, .avTransport, "Stop", ["InstanceID": "0"])
            }
            hold.rooms = []
            hold.leader = nil
        }
    }

    /// A Room switched on during a Session is taken over at once. One
    /// switched off stops and leaves the group; if it led, the rest re-form
    /// under a new leader. Switching off also ends a Step back from it.
    func roomSwitched(_ id: RoomState.ID, on: Bool) {
        // Outside a Session, the next Session's Takeover picks it up.
        if on, case .idle = state.session { return }
        enqueueSonos { [weak self] in
            guard let self else { return }
            if on {
                await takeOver([id])
            } else {
                setSteppedBack(false, id)
                await release(id)
            }
        }
    }

    /// During a Session, takes over switched-on Rooms that aren't held yet:
    /// found late, or back on the network.
    func takeOverMissingRooms() {
        guard case .running = state.session else { return }
        enqueueSonos { [weak self] in
            guard let self, case .running = state.session else { return }
            await takeOver(state.rooms.filter(\.isOn).map(\.id))
        }
    }

    /// A held Room gone from the network is let go without a Step back, so
    /// it rejoins when it returns. If it led, the rest re-form.
    func roomLost(at host: String) {
        enqueueSonos { [weak self] in
            guard let self, let id = roomHosts.first(where: { $0.value == host })?.key,
                  hold.rooms.contains(id)
            else { return }
            hold.rooms.remove(id)
            if hold.leader == id {
                await reform()
            }
        }
    }

    /// Lets go of a held Room: it leaves the group, then stops.
    private func release(_ id: RoomState.ID) async {
        guard hold.rooms.contains(id), let host = roomHosts[id] else { return }
        hold.rooms.remove(id)
        // Leaving first, so a group it led plays on until it re-forms.
        try? await send(host, .avTransport, "BecomeCoordinatorOfStandaloneGroup", ["InstanceID": "0"])
        try? await send(host, .avTransport, "Stop", ["InstanceID": "0"])
        if hold.leader == id {
            await reform()
        }
    }

    /// Chooses a new leader among the held Rooms; the rest join it.
    func reform() async {
        let rest = Array(hold.rooms)
        hold.rooms = []
        hold.leader = nil
        await takeOver(rest)
    }

    func setSteppedBack(_ steppedBack: Bool, _ id: RoomState.ID) {
        guard let index = state.rooms.firstIndex(where: { $0.id == id }) else { return }
        state.rooms[index].isSteppedBack = steppedBack
    }

    /// Sets a held Room's volume at once.
    func roomVolumeChanged(_ id: RoomState.ID) {
        guard let volume = state.rooms.first(where: { $0.id == id })?.volume else { return }
        enqueueSonos { [weak self] in
            guard let self, hold.rooms.contains(id), let host = roomHosts[id] else { return }
            try? await setVolume(volume, of: id, at: host)
        }
    }

    /// Takes these Rooms over: they join the leader, or, with no leader, the
    /// first that takes the stream leads and the rest join it. Rooms that
    /// can't be reached are skipped and flagged.
    func takeOver(_ ids: [RoomState.ID]) async {
        guard let address = streamSink.localAddress else { return }
        let uri = "x-rincon-mp3radio://\(address):\(Self.streamPort)\(Self.streamPath)"
        await refreshTopology(from: ids + hold.rooms)
        // In name order, as the main screen lists them.
        var candidates = state.rooms
            .filter { ids.contains($0.id) && $0.isReachable && !$0.isSteppedBack && roomHosts[$0.id] != nil && !hold.rooms.contains($0.id) }
            .map(\.id)
        let ours = Set(candidates).union(hold.rooms)
        if hold.leader == nil {
            while !candidates.isEmpty {
                let id = candidates.removeFirst()
                if await lead(id, uri: uri, ours: ours) {
                    hold.leader = id
                    hold.rooms.insert(id)
                    break
                }
            }
        }
        guard let leader = hold.leader else { return }
        for id in candidates where isReachable(id) {
            if await join(id, leader: leader, ours: ours) {
                hold.rooms.insert(id)
            }
        }
    }

    private func lead(_ id: RoomState.ID, uri: String, ours: Set<String>) async -> Bool {
        guard let host = roomHosts[id], let volume = volume(of: id) else { return false }
        do {
            // The stream can only be set on a coordinator, and the Room must
            // not drag a Room that isn't ours along.
            if isGroupedWithOthers(id, ours: ours) || coordinator(of: id) != id {
                try await send(host, .avTransport, "BecomeCoordinatorOfStandaloneGroup", ["InstanceID": "0"])
            }
            try await send(host, .avTransport, "SetAVTransportURI", [
                "InstanceID": "0",
                "CurrentURI": uri,
                "CurrentURIMetaData": Self.stationMetadata,
            ])
            try await setVolume(volume, of: id, at: host)
            try await send(host, .avTransport, "Play", ["InstanceID": "0", "Speed": "1"])
            return true
        } catch {
            return false
        }
    }

    private func join(_ id: RoomState.ID, leader: RoomState.ID, ours: Set<String>) async -> Bool {
        guard let host = roomHosts[id], let volume = volume(of: id) else { return false }
        do {
            if isGroupedWithOthers(id, ours: ours) {
                try await send(host, .avTransport, "BecomeCoordinatorOfStandaloneGroup", ["InstanceID": "0"])
            }
            try await send(host, .avTransport, "SetAVTransportURI", [
                "InstanceID": "0",
                "CurrentURI": "x-rincon:\(leader)",
                "CurrentURIMetaData": "",
            ])
            try await setVolume(volume, of: id, at: host)
            return true
        } catch {
            return false
        }
    }

    func setVolume(_ volume: Int, of id: RoomState.ID, at host: String) async throws {
        try await send(host, .renderingControl, "SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "\(volume)"])
        hold.volumes[id] = volume
    }

    /// Reads the household's groups from the first of these Rooms that answers.
    func refreshTopology(from ids: [RoomState.ID]) async {
        for id in ids {
            guard let host = roomHosts[id], isReachable(id) else { continue }
            let request = SOAP.request(host: host, .zoneGroupTopology, "GetZoneGroupState", [:])
            if let xml = try? await outArguments(of: request, host: host)["ZoneGroupState"] {
                applyTopology(ZoneGroupState.rooms(in: xml))
                return
            }
        }
    }

    func coordinator(of id: RoomState.ID) -> String? {
        hold.topology.first { $0.id == id }?.coordinator
    }

    /// The Room shares its Sonos group with a Room that isn't ours.
    private func isGroupedWithOthers(_ id: RoomState.ID, ours: Set<String>) -> Bool {
        guard let coordinator = coordinator(of: id) else { return false }
        return hold.topology.contains { $0.coordinator == coordinator && !ours.contains($0.id) }
    }

    private func volume(of id: RoomState.ID) -> Int? {
        state.rooms.first { $0.id == id }?.volume
    }

    func isReachable(_ id: RoomState.ID) -> Bool {
        state.rooms.first { $0.id == id }?.isReachable ?? false
    }

    /// Runs Sonos commands one at a time, in the order they were asked for,
    /// so a Stop never overtakes the Takeover it ends.
    func enqueueSonos(_ work: @escaping @MainActor () async -> Void) {
        let previous = sonosQueue
        sonosQueue = Task {
            await previous?.value
            await work()
        }
    }

    func send(_ host: String, _ service: SonosService, _ action: String, _ args: KeyValuePairs<String, String>) async throws {
        _ = try await outArguments(of: SOAP.request(host: host, service, action, args), host: host)
    }

    /// Sends a request and reads its answer. A Room that can't be reached at
    /// all is flagged; one that answers, even with a fault, is reachable.
    func outArguments(of request: HTTPRequest, host: String) async throws -> [String: String] {
        let response: HTTPResponse
        do {
            response = try await sonos.send(request)
        } catch {
            setReachable(false, host: host)
            throw error
        }
        setReachable(true, host: host)
        return try SOAP.outArguments(of: response)
    }

    func setReachable(_ reachable: Bool, host: String) {
        for index in state.rooms.indices where roomHosts[state.rooms[index].id] == host {
            if state.rooms[index].isReachable != reachable {
                state.rooms[index].isReachable = reachable
            }
        }
    }
}
