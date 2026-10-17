import Foundation

public enum MenuLinkEvent: Sendable, Equatable {
    /// The link to Pressing on the iPhone is up.
    case connected
    /// A message arrived from the phone.
    case received(Data)
    /// The link went down, or connecting to the Pressing found failed.
    case disconnected
}

/// Port: Pressing Menu's side of the link to the phone. Production: finds
/// `_pressing._tcp` over Bonjour and opens a WebSocket to the first Pressing
/// it finds (ADR-0004).
@MainActor
public protocol MenuLink: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (MenuLinkEvent) -> Void)
    /// Looks for Pressing until it finds it, then connects and reports
    /// `.connected`. Reports `.disconnected` when connecting fails or the
    /// link drops; Pressing Menu calls it again to retry.
    func connect()
    /// Sends one message to the phone.
    func send(_ message: Data)
}
