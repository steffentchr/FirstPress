import Foundation

/// Takeover at the start of a Session and Stop at its end.
///
/// Every switched-on Room plays the stream on its own. Grouping the Rooms so
/// they play in sync, mid-Session switching and Step back come later
/// (ticket #4).
extension Pressing {
    /// What Sonos shows as the station: SoCo's title-only radio DIDL-Lite.
    static let stationMetadata = #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="R:0/0/0" parentID="R:0/0" restricted="true"><dc:title>Pressing</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item></DIDL-Lite>"#

    /// Takes over every switched-on Room Pressing knows where to reach.
    func takeOverRooms() {
        guard let address = streamSink.localAddress else { return }
        let uri = "x-rincon-mp3radio://\(address):\(Self.streamPort)\(Self.streamPath)"
        for room in state.rooms where room.isOn {
            guard let host = roomHosts[room.id] else { continue }
            heldRooms.insert(room.id)
            let volume = room.volume
            enqueueSonos { [weak self] in
                guard let self else { return }
                do {
                    try await send(host, .avTransport, "SetAVTransportURI", [
                        "InstanceID": "0",
                        "CurrentURI": uri,
                        "CurrentURIMetaData": Self.stationMetadata,
                    ])
                    try await send(host, .renderingControl, "SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "\(volume)"])
                    try await send(host, .avTransport, "Play", ["InstanceID": "0", "Speed": "1"])
                } catch {
                    // The Room keeps what it was doing; the others still play.
                }
            }
        }
    }

    /// Stops the held Rooms: Stop only, no ungrouping and no restore.
    func stopRooms() {
        for id in heldRooms {
            guard let host = roomHosts[id] else { continue }
            enqueueSonos { [weak self] in
                try? await self?.send(host, .avTransport, "Stop", ["InstanceID": "0"])
            }
        }
        heldRooms = []
    }

    /// Sets a held Room's volume at once.
    func roomVolumeChanged(_ id: RoomState.ID) {
        guard heldRooms.contains(id), let host = roomHosts[id],
              let volume = state.rooms.first(where: { $0.id == id })?.volume
        else { return }
        enqueueSonos { [weak self] in
            try? await self?.send(host, .renderingControl, "SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "\(volume)"])
        }
    }

    /// Runs Sonos commands one at a time, in the order they were asked for,
    /// so a Stop never overtakes the Takeover it ends.
    private func enqueueSonos(_ work: @escaping @MainActor () async -> Void) {
        let previous = sonosQueue
        sonosQueue = Task {
            await previous?.value
            await work()
        }
    }

    private func send(_ host: String, _ service: SonosService, _ action: String, _ args: KeyValuePairs<String, String>) async throws {
        let response = try await sonos.send(SOAP.request(host: host, service, action, args))
        _ = try SOAP.outArguments(of: response)
    }
}
