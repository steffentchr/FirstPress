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
    }

    /// How long Pressing Menu says it's looking before it says the iPhone
    /// can't be reached. It goes on looking after that.
    public static let lookingFor: TimeInterval = 5

    public private(set) var connection = Connection.looking
    /// The last snapshot from the phone, kept while it can't be reached.
    private var snapshot: MenuSnapshot?

    public var header: Header {
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

    /// A Record is playing on the phone, in a Gap or not: the menu-bar icon
    /// changes subtly.
    public var isRecordPlaying: Bool {
        guard connection == .connected, let record = snapshot?.record else { return false }
        return record != .flipped
    }

    @ObservationIgnored private let link: any MenuLink
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var lookingTimer: (any ScheduledWork)?

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
            connection = .connected
        case .disconnected:
            connection = .cantBeReached
        case .received(let data):
            if case .snapshot(let snapshot) = MenuWire.decode(data) {
                self.snapshot = snapshot
            }
        }
    }
}
