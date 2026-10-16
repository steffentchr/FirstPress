import Foundation

/// Launch recovery: Rooms still on a Pressing stream when Pressing starts
/// were held before a restart. Switched-on ones are taken into a Session
/// with signal and stopped without; switched-off ones are stopped at once.
/// Either way no Room stays stuck on a dead stream, and a Room playing
/// anything else gets no command.
extension Pressing {
    /// How long after finding them Pressing waits for a Record to start
    /// before it stops recovered Rooms: the start delay, plus time for the
    /// level to settle.
    var recoveryGrace: TimeInterval { settings.detection.startDelay + 3 }

    /// Once per launch, after the first topology read: asks each Room that
    /// leads its Sonos group what it plays.
    func recoverRoomsAtLaunch() {
        guard !hold.hasLookedForRecovery, !hold.topology.isEmpty else { return }
        hold.hasLookedForRecovery = true
        enqueueSonos { [weak self] in
            guard let self else { return }
            var recovered: [RoomState.ID] = []
            for room in state.rooms where coordinator(of: room.id) == room.id {
                guard let host = roomHosts[room.id] else { continue }
                let request = SOAP.request(host: host, .avTransport, "GetMediaInfo", ["InstanceID": "0"])
                guard let uri = try? await outArguments(of: request, host: host)["CurrentURI"], Self.isPressingStream(uri) else { continue }
                if room.isOn {
                    recovered.append(room.id)
                } else {
                    // Never taken into a Session: one Stop, and left alone.
                    try? await send(host, .avTransport, "Stop", ["InstanceID": "0"])
                }
            }
            guard !recovered.isEmpty else { return }
            // A Session that starts in the meantime takes them over like any
            // switched-on Room, at this phone's current address.
            hold.recovery = scheduler.schedule(after: recoveryGrace) { [weak self] in
                guard let self, case .idle = state.session else { return }
                stopRecovered(recovered)
            }
        }
    }

    private func stopRecovered(_ ids: [RoomState.ID]) {
        enqueueSonos { [weak self] in
            guard let self else { return }
            for id in ids where !hold.rooms.contains(id) {
                guard let host = roomHosts[id] else { continue }
                try? await send(host, .avTransport, "Stop", ["InstanceID": "0"])
            }
        }
    }
}
