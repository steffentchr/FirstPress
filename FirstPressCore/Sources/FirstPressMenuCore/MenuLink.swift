import Foundation

public enum MenuLinkEvent: Sendable, Equatable {
    /// The link to First Press on the iPhone is up.
    case connected
    /// A message arrived from the phone.
    case received(Data)
    /// The link went down, or connecting to the First Press found failed.
    case disconnected
    /// macOS hasn't allowed First Press Menu on the local network, so
    /// looking for First Press waits. The link goes on by itself once it is
    /// allowed, and reports `.connected` when it finds the phone.
    case localNetworkDenied
}

/// Port: First Press Menu's side of the link to the phone. Production: finds
/// `_firstpress._tcp` over Bonjour and opens a WebSocket to the first First Press
/// it finds (ADR-0004).
@MainActor
public protocol MenuLink: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void)
    /// Looks for First Press until it finds it, then connects and reports
    /// `.connected`. Reports `.disconnected` when connecting fails or the
    /// link drops; First Press Menu calls it again to retry.
    func connect()
    /// Sends one message to the phone.
    func send(_ message: Data)
}
