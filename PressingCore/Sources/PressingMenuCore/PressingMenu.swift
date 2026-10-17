import Foundation
import Observation
import PressingCore

/// Pressing Menu's model: the link to Pressing on the iPhone, and what the
/// panel and the menu-bar icon show. The Mac app renders it.
@MainActor
@Observable
public final class PressingMenu {
    /// What the panel's header shows.
    public enum Header: Sendable, Equatable {
        /// The current Track: its title large, the artist beneath.
        case track(Track)
    }

    public private(set) var header: Header?

    @ObservationIgnored private let link: any MenuLink
    @ObservationIgnored private let scheduler: any Scheduler

    public init(link: any MenuLink, scheduler: any Scheduler) {
        self.link = link
        self.scheduler = scheduler
    }

    /// Call once at launch: starts looking for Pressing.
    public func start() {
        link.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        link.connect()
    }

    private func handle(_ event: MenuLinkEvent) {
        switch event {
        case .connected, .disconnected:
            break
        case .received(let data):
            if case .snapshot(let snapshot) = MenuWire.decode(data), let track = snapshot.track {
                header = .track(track)
            }
        }
    }
}
