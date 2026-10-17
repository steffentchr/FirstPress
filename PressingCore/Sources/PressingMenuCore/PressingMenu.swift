import Foundation
import Observation
import PressingCore

/// Pressing Menu's model: the link to Pressing on the iPhone, and what the
/// panel and the menu-bar icon show. Pressing Menu's views render it.
@MainActor
@Observable
public final class PressingMenu {
    public enum Connection: Sendable, Equatable {
        /// Looking for Pressing on the network, not found yet.
        case looking
        /// Linked to Pressing on the iPhone.
        case connected
        /// Pressing isn't running, the phone is off the network, or the
        /// link dropped. The last snapshot stays on screen, greyed, while
        /// Pressing Menu keeps trying.
        case cantBeReached
        /// The phone speaks a newer major version of the wire contract than
        /// this Pressing Menu. It shows nothing from it and sends nothing.
        case needsUpdate
    }

    /// What the panel's header shows.
    public enum Header: Sendable, Equatable {
        /// The current Track: its title large, the artist beneath.
        case track(Track)
        case lookingForPressing
        case cantBeReached
        /// No Session is running, or the phone asks for its input.
        case waitingForRecord
        /// A Record is playing and no Track is identified yet.
        case recordNotIdentified
        /// The phone is newer than this Pressing Menu can follow.
        case updatePressingMenu
    }

    /// How long Pressing Menu says it's looking before it says the iPhone
    /// can't be reached. It goes on looking after that.
    public static let lookingFor: TimeInterval = 5
    /// How long Pressing Menu waits before trying again: doubling from 1 s
    /// after each failed attempt, to at most 30 s.
    static let retryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    public private(set) var connection = Connection.looking

    /// The panel is showing. No Track gets a notification meanwhile: the
    /// listener can see it already.
    @ObservationIgnored public var isPanelOpen = false
    /// The "Notify on new Track" setting, on by default. Pressing Menu keeps
    /// it in its user defaults and sets it here.
    @ObservationIgnored public var notifiesOnNewTrack = true
    /// The last snapshot from the phone, kept while it can't be reached.
    private var snapshot: MenuSnapshot?

    public var header: Header {
        if connection == .needsUpdate { return .updatePressingMenu }
        guard let snapshot else {
            return connection == .cantBeReached ? .cantBeReached : .lookingForPressing
        }
        if let track = snapshot.track { return .track(track) }
        if connection == .cantBeReached { return .cantBeReached }
        switch (snapshot.page, snapshot.record) {
        case (.nowPlaying, .playing), (.nowPlaying, .gap): return .recordNotIdentified
        default: return .waitingForRecord
        }
    }

    /// History as the panel lists it under the header: at most 10 Tracks,
    /// newest first, each once, the current one left out. Kept, greyed,
    /// while the phone can't be reached.
    public var history: [Track] {
        snapshot?.recentPlays.map(\.track) ?? []
    }

    /// The Sonos Rooms Pressing has found, by name, as the phone's Rooms
    /// sheet lists them. Kept, greyed, while the phone can't be reached.
    public var rooms: [MenuSnapshot.Room] {
        (snapshot?.rooms ?? []).map { room in
            // A slider being dragged shows where it is, not the phone's last
            // answer, which can lag behind while volumes are held back.
            guard let volume = draggedVolumes[room.id] else { return room }
            var dragged = room
            dragged.volume = volume
            return dragged
        }
    }

    /// This iPhone, the Phone output. Nil before the first snapshot, or from
    /// an older phone that doesn't send it.
    public var phoneOutput: MenuSnapshot.PhoneOutput? {
        snapshot?.phoneOutput
    }

    /// Where Pressing plays, as the footer says it: the first switched-on
    /// Room's name plus "+N" for the others, This iPhone counted, or "No
    /// Rooms". The Rooms name This iPhone only when no Room is on. Outside a
    /// Session these are the choices for the next one.
    public var roomsSummary: String {
        var names = rooms.filter(\.isOn).map(\.name)
        if phoneOutput?.isOn == true { names.append("This iPhone") }
        guard let first = names.first else { return "No Rooms" }
        return names.count == 1 ? first : "\(first) +\(names.count - 1)"
    }

    public func room(_ id: MenuSnapshot.Room.ID) -> MenuSnapshot.Room? {
        rooms.first { $0.id == id }
    }

    /// The Rooms controls work only while linked to the phone.
    public var canControl: Bool { connection == .connected }

    /// Switches a Room on or off on the phone, at once: mid-Session it is
    /// taken over or let go; outside one it is chosen for the next.
    public func switchRoom(_ id: MenuSnapshot.Room.ID, on: Bool) {
        send(.switchRoom(id: id, on: on))
    }

    /// Sets a Room's volume on the phone, 0 to 100: a click, or the end of
    /// a drag. Sent at once.
    public func setVolume(_ volume: Int, for id: MenuSnapshot.Room.ID) {
        volumeTimers.removeValue(forKey: id)?.cancel()
        draggedVolumes[id] = nil
        sendVolume(volume, for: id)
    }

    /// A Room's volume slider moved while being dragged. The phone hears at
    /// most one volume per `volumeInterval`, the latest each time, so the
    /// Room follows the drag without flooding the phone. Call `setVolume`
    /// on release.
    public func dragVolume(_ volume: Int, for id: MenuSnapshot.Room.ID) {
        guard canControl else { return }
        draggedVolumes[id] = volume
        guard volumeTimers[id] == nil else { return }
        let elapsed = lastVolumeSent[id].map { scheduler.now.timeIntervalSince($0) } ?? .infinity
        if elapsed >= Self.volumeInterval {
            sendVolume(volume, for: id)
            return
        }
        volumeTimers[id] = scheduler.schedule(after: Self.volumeInterval - elapsed) { [weak self] in
            guard let self else { return }
            volumeTimers[id] = nil
            if let latest = draggedVolumes[id] { sendVolume(latest, for: id) }
        }
    }

    /// The shortest time between two volumes sent while a slider is dragged:
    /// about 10 a second.
    public static let volumeInterval: TimeInterval = 0.1

    private func sendVolume(_ volume: Int, for id: MenuSnapshot.Room.ID) {
        lastVolumeSent[id] = scheduler.now
        send(.setVolume(id: id, volume: volume))
    }

    /// Switches This iPhone on or off on the phone.
    public func switchPhoneOutput(on: Bool) {
        send(.switchPhoneOutput(on: on))
    }

    private func send(_ command: MenuCommand) {
        guard canControl else { return }
        link.send(MenuWire.encode(command))
    }

    /// A Record is playing on the phone, in a Gap or not: the menu-bar icon
    /// changes subtly.
    public var isRecordPlaying: Bool {
        guard connection == .connected, let record = snapshot?.record else { return false }
        return record != .flipped
    }

    /// Volumes of sliders being dragged, by Room.
    private var draggedVolumes: [MenuSnapshot.Room.ID: Int] = [:]
    @ObservationIgnored private var lastVolumeSent: [MenuSnapshot.Room.ID: Date] = [:]
    @ObservationIgnored private var volumeTimers: [MenuSnapshot.Room.ID: any ScheduledWork] = [:]
    @ObservationIgnored private let link: any MenuLink
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let notifier: (any TrackNotifier)?
    @ObservationIgnored private var lookingTimer: (any ScheduledWork)?
    @ObservationIgnored private var retryTimer: (any ScheduledWork)?
    /// Failed attempts since the link was last up.
    @ObservationIgnored private var failures = 0
    /// The link is up and its first snapshot hasn't arrived: the Track in
    /// it was already playing, so it gets no notification.
    @ObservationIgnored private var awaitingFirstSnapshot = false

    public init(link: any MenuLink, scheduler: any Scheduler, notifier: (any TrackNotifier)? = nil) {
        self.link = link
        self.scheduler = scheduler
        self.notifier = notifier
    }

    /// Call once at launch: starts looking for Pressing.
    public func start() {
        link.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        lookingTimer = scheduler.schedule(after: Self.lookingFor) { [weak self] in
            guard let self, connection == .looking else { return }
            connection = .cantBeReached
        }
        link.connect()
    }

    private func handle(_ event: MenuLinkEvent) {
        switch event {
        case .connected:
            lookingTimer?.cancel()
            lookingTimer = nil
            failures = 0
            awaitingFirstSnapshot = true
            connection = .connected
        case .disconnected:
            connection = .cantBeReached
            retry()
        case .received(let data):
            switch MenuWire.decode(data) {
            case .snapshot(let snapshot):
                notifyIfNew(snapshot.track)
                self.snapshot = snapshot
                connection = .connected
            case .newerMajor:
                snapshot = nil
                connection = .needsUpdate
            case .unknown:
                break
            }
        }
    }

    /// One notification for each Track identified while connected: not the
    /// one already playing when the link comes up.
    private func notifyIfNew(_ track: Track?) {
        defer { awaitingFirstSnapshot = false }
        // The same Track, even once its album or cover is filled in.
        guard !awaitingFirstSnapshot, let track, snapshot?.track.map(track.isSame) != true else { return }
        guard notifiesOnNewTrack, !isPanelOpen else { return }
        notifier?.notify(newTrack: track)
    }

    private func retry() {
        let delay = Self.retryDelays[min(failures, Self.retryDelays.count - 1)]
        failures += 1
        retryTimer?.cancel()
        retryTimer = scheduler.schedule(after: delay) { [weak self] in
            self?.link.connect()
        }
    }
}

/// Why a switched-on Room may be quiet, as the phone's Rooms sheet marks it.
public enum RoomMarker: Sendable, Equatable {
    /// The Room stopped answering.
    case cantBeReached
    /// Someone took it over in the Sonos app, so Pressing stepped back:
    /// switching it off and on takes it back.
    case takenOverInSonosApp
}

extension MenuSnapshot.Room {
    /// The marker the Rooms view shows, as the phone shows it.
    public var marker: RoomMarker? {
        if !isReachable { return .cantBeReached }
        if isSteppedBack { return .takenOverInSonosApp }
        return nil
    }
}

extension MenuSnapshot.PhoneOutput {
    /// Where This iPhone plays, such as "AirPlay: Kitchen", "iPhone speaker"
    /// or "AirPods". Nil while the phone reports no route.
    public var whereItPlays: String? { route?.label }
}
