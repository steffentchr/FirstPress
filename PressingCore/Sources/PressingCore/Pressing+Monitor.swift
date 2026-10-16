import Foundation

/// The Session monitor: every few seconds during a Session, Pressing reads
/// what its Rooms are doing and steps back from any someone else took over.
extension Pressing {
    /// How often the held Rooms are read.
    static let monitorInterval: TimeInterval = 5

    /// What a leader still on the stream but not playing means.
    enum NotPlayingPolicy {
        /// A dropout: tell it to play again.
        case resume
        /// Someone paused it in the Sonos app: step back.
        case stepBack
    }

    /// Sonos reports a dropped stream as STOPPED and a pause as
    /// PAUSED_PLAYBACK, as far as anyone has written down, but whether a dead
    /// `x-rincon-mp3radio` stream ever reports PAUSED_PLAYBACK is unverified
    /// (a device test). Until the two can be told apart, both resume.
    static let pausedPolicy = NotPlayingPolicy.resume

    func startMonitor() {
        hold.monitor?.cancel()
        hold.monitor = scheduler.schedule(after: Self.monitorInterval) { [weak self] in
            self?.monitorTick()
        }
    }

    func stopMonitor() {
        hold.monitor?.cancel()
        hold.monitor = nil
    }

    private func monitorTick() {
        startMonitor()
        // A Room that doesn't answer can hold a read up for seconds; never
        // queue a second read behind one still waiting.
        guard !hold.isPolling else { return }
        hold.isPolling = true
        enqueueSonos { [weak self] in
            await self?.poll()
            self?.hold.isPolling = false
        }
    }

    private func poll() async {
        guard case .running = state.session, let leader = hold.leader, let leaderHost = roomHosts[leader] else { return }
        await refreshTopology(from: [leader] + hold.rooms.filter { $0 != leader })

        // The leader: is it still playing our stream?
        let mediaRequest = SOAP.request(host: leaderHost, .avTransport, "GetMediaInfo", ["InstanceID": "0"])
        let media: [String: String]
        do {
            media = try await outArguments(of: mediaRequest, host: leaderHost)
        } catch {
            if !isReachable(leader) {
                // The leader is gone; the rest play on under a new one.
                hold.rooms.remove(leader)
                await reform()
            }
            return
        }
        guard Self.isPressingStream(media["CurrentURI"] ?? "") else {
            // Someone chose something else for the whole group.
            stepBack(from: hold.rooms)
            return
        }

        // The members: is each still in the leader's group?
        for id in hold.rooms where id != leader {
            guard let room = hold.topology.first(where: { $0.id == id }) else { continue }
            if room.coordinator != leader {
                stepBack(from: [id])
            }
        }

        // Transport state is only true on the leader: members always say PLAYING.
        let transportRequest = SOAP.request(host: leaderHost, .avTransport, "GetTransportInfo", ["InstanceID": "0"])
        if let transport = try? await outArguments(of: transportRequest, host: leaderHost)["CurrentTransportState"] {
            switch transport {
            case "PLAYING", "TRANSITIONING":
                break
            case "PAUSED_PLAYBACK" where Self.pausedPolicy == .stepBack:
                stepBack(from: hold.rooms)
                return
            default:
                try? await send(leaderHost, .avTransport, "Play", ["InstanceID": "0", "Speed": "1"])
            }
        }

        // Volumes: a change made in the Sonos app or on the speaker is adopted.
        for id in hold.rooms {
            guard let host = roomHosts[id] else { continue }
            let request = SOAP.request(host: host, .renderingControl, "GetVolume", ["InstanceID": "0", "Channel": "Master"])
            guard let read = try? await outArguments(of: request, host: host)["CurrentVolume"],
                  let volume = Int(read), volume != hold.volumes[id]
            else { continue }
            hold.volumes[id] = volume
            updateChoice(for: id) { $0.volume = volume }
        }
    }

    /// Lets go of these Rooms without a word to them, for the rest of the Session.
    private func stepBack(from ids: Set<RoomState.ID>) {
        for id in ids {
            hold.rooms.remove(id)
            setSteppedBack(true, id)
        }
        if let leader = hold.leader, ids.contains(leader) {
            hold.leader = nil
        }
    }
}
