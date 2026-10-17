import Foundation
import Observation
import PressingCore

/// Pressing Menu's model: the link to Pressing on the iPhone, and what the
/// panel and the menu-bar icon show. The Mac app renders it.
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
        snapshot?.rooms ?? []
    }

    /// This iPhone, the Phone output. Nil before the first snapshot, or from
    /// an older phone that doesn't send it.
    public var phoneOutput: MenuSnapshot.PhoneOutput? {
        snapshot?.phoneOutput
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

    /// Sets a Room's volume on the phone, 0 to 100.
    public func setVolume(_ volume: Int, for id: MenuSnapshot.Room.ID) {
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

    @ObservationIgnored private let link: any MenuLink
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var lookingTimer: (any ScheduledWork)?
    @ObservationIgnored private var retryTimer: (any ScheduledWork)?
    /// Failed attempts since the link was last up.
    @ObservationIgnored private var failures = 0

    public init(link: any MenuLink, scheduler: any Scheduler) {
        self.link = link
        self.scheduler = scheduler
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
            connection = .connected
        case .disconnected:
            connection = .cantBeReached
            retry()
        case .received(let data):
            switch MenuWire.decode(data) {
            case .snapshot(let snapshot):
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
