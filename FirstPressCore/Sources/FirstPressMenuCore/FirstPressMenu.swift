import Foundation
import Observation
import FirstPressCore

/// First Press Menu's model: the link to First Press on the iPhone, and what the
/// panel and the menu-bar icon show. First Press Menu's views render it.
@MainActor
@Observable
public final class FirstPressMenu {
    public enum Connection: Sendable, Equatable {
        /// Looking for First Press on the network, not reached yet: from launch
        /// until the first link is up, however long that takes.
        case looking
        /// Linked to First Press on the iPhone.
        case connected
        /// A live link dropped: First Press stopped running, or the phone left
        /// the network. The last snapshot stays on screen, greyed, while
        /// First Press Menu keeps trying.
        case cantBeReached
        /// The phone speaks a newer major version of the wire contract than
        /// this First Press Menu. It shows nothing from it and sends nothing.
        case needsUpdate
    }

    /// What the panel's header shows.
    public enum Header: Sendable, Equatable {
        /// The current Track: its title large, the artist beneath.
        case track(Track)
        /// No phone is connected: First Press hasn't been found yet, or a live
        /// link dropped and no Track is kept to show. The panel says only
        /// that it's looking for First Press, small.
        case lookingForFirstPress
        /// No Session is running, or the phone asks for its input.
        case waitingForRecord
        /// A Record is playing and no Track is identified yet.
        case recordNotIdentified
        /// The last Record ended with a Flip and the Session still runs:
        /// "Between sides", with the Session's last Track small beneath, if
        /// one was identified.
        case betweenSides(lastTrack: Track?)
        /// The phone is newer than this First Press Menu can follow.
        case updateFirstPressMenu
        /// No phone is connected and macOS hasn't allowed First Press Menu
        /// on the local network, so it can't look for First Press. The panel
        /// says, small, where to allow it.
        case allowLocalNetwork
    }

    /// How long First Press Menu waits before trying again: doubling from 1 s
    /// after each failed attempt, to at most 30 s.
    static let retryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    public private(set) var connection = Connection.looking

    /// The panel is showing. No notification is posted meanwhile, for a new
    /// Track or a Flip: the listener can see it already.
    @ObservationIgnored public var isPanelOpen = false
    /// The Notifications setting, for new Tracks and Flips, on by default.
    /// First Press Menu keeps it in its user defaults (under its first name,
    /// "notifiesOnNewTrack") and sets it here.
    public var notificationsAreOn = true
    /// The listener turned notifications off for First Press Menu in System
    /// Settings. The notifications adapter reads it from macOS and sets it
    /// here.
    public var notificationsAreDenied = false
    /// New Tracks and Flips get a notification: the setting is on and macOS
    /// allows them. Settings shows the switch this way.
    public var postsNotifications: Bool {
        notificationsAreOn && !notificationsAreDenied
    }
    /// The last snapshot from the phone, kept while it can't be reached.
    private var snapshot: MenuSnapshot?
    /// The link says macOS hasn't allowed First Press Menu on the local
    /// network. Until the link is up again.
    private var isLocalNetworkDenied = false

    public var header: Header {
        if connection == .needsUpdate { return .updateFirstPressMenu }
        let notFound: Header = isLocalNetworkDenied ? .allowLocalNetwork : .lookingForFirstPress
        guard let snapshot else { return notFound }
        if let track = snapshot.track { return .track(track) }
        // After a drop-out only a Track is kept on screen.
        if connection == .cantBeReached { return notFound }
        if snapshot.page == .nowPlaying, snapshot.record == .flipped {
            return .betweenSides(lastTrack: snapshot.lastTrack)
        }
        switch (snapshot.page, snapshot.record) {
        case (.nowPlaying, .playing), (.nowPlaying, .gap): return .recordNotIdentified
        default: return .waitingForRecord
        }
    }

    /// After a drop-out, with the last Track kept on screen, greyed, a small
    /// line beneath it says First Press Menu is looking for First Press. When the
    /// header says so itself, there is no line.
    public var showsLookingLine: Bool {
        showsLineBeneathTrack && !isLocalNetworkDenied
    }

    /// As the looking line, beneath a kept Track, when First Press Menu
    /// can't look because macOS hasn't allowed it on the local network: it
    /// says where to allow it instead.
    public var showsLocalNetworkLine: Bool {
        showsLineBeneathTrack && isLocalNetworkDenied
    }

    private var showsLineBeneathTrack: Bool {
        guard connection == .cantBeReached else { return false }
        if case .track = header { return true }
        return false
    }

    /// History as the panel lists it under the header: at most 10 Tracks,
    /// newest first, each once, the current one left out. Kept, greyed,
    /// while the phone can't be reached.
    public var history: [Track] {
        snapshot?.recentPlays.map(\.track) ?? []
    }

    /// The Sonos Rooms First Press has found, by name, as the phone's Rooms
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

    /// Where First Press plays, as the footer says it: the first switched-on
    /// Room's name plus "+N" for the others, This iPhone counted, or "No
    /// Rooms". The Rooms name This iPhone only when no Room is on. Outside a
    /// Session these are the choices for the next one. Nil, and not shown,
    /// while no phone is connected.
    public var roomsSummary: String? {
        guard canControl else { return nil }
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
    @ObservationIgnored private let notifier: (any MenuNotifier)?
    @ObservationIgnored private var retryTimer: (any ScheduledWork)?
    /// Failed attempts since the link was last up.
    @ObservationIgnored private var failures = 0
    /// The link is up and its first snapshot hasn't arrived: the Track in
    /// it was already playing, so it gets no notification.
    @ObservationIgnored private var awaitingFirstSnapshot = false
    /// A "Flip the record" notification was posted and not removed yet.
    @ObservationIgnored private var isFlipNotificationPosted = false

    public init(link: any MenuLink, scheduler: any Scheduler, notifier: (any MenuNotifier)? = nil) {
        self.link = link
        self.scheduler = scheduler
        self.notifier = notifier
    }

    /// Call once at launch: starts looking for First Press.
    public func start() {
        link.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        link.connect()
    }

    private func handle(_ event: MenuLinkEvent) {
        switch event {
        case .connected:
            isLocalNetworkDenied = false
            failures = 0
            awaitingFirstSnapshot = true
            connection = .connected
        case .disconnected:
            // Until First Press has been reached once, a failed attempt is
            // still looking.
            if connection != .looking { connection = .cantBeReached }
            retry()
        case .localNetworkDenied:
            isLocalNetworkDenied = true
        case .received(let data):
            switch MenuWire.decode(data) {
            case .snapshot(let snapshot):
                notifyIfNew(snapshot.track)
                notifyIfFlipped(snapshot)
                awaitingFirstSnapshot = false
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
        // The same Track, even once its album or cover is filled in.
        guard !awaitingFirstSnapshot, let track, snapshot?.track.map(track.isSame) != true else { return }
        guard postsNotifications, !isPanelOpen else { return }
        notifier?.notify(newTrack: track)
    }

    /// "Flip the record" when the Record ends with a Flip during a Session:
    /// not for a Flip already in progress when the link comes up. Removed
    /// again once the next Record starts, but not when the Session ends by
    /// itself.
    private func notifyIfFlipped(_ next: MenuSnapshot) {
        if isFlipNotificationPosted, next.record == .playing || next.record == .gap {
            isFlipNotificationPosted = false
            notifier?.removeFlip()
        }
        guard !awaitingFirstSnapshot, next.record == .flipped, snapshot?.record != .flipped else { return }
        guard postsNotifications, !isPanelOpen else { return }
        isFlipNotificationPosted = true
        notifier?.notifyFlip(lastTrack: next.lastTrack)
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

extension MenuSnapshot.PhoneOutput {
    /// Where This iPhone plays, such as "AirPlay: Kitchen", "iPhone speaker"
    /// or "AirPods". Nil while the phone reports no route.
    public var whereItPlays: String? { route?.label }
}
