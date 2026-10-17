import Foundation

/// One Pressing Menu connected to the phone.
public struct MenuClientID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public enum MenuServerEvent: Sendable, Equatable {
    /// A Pressing Menu connected.
    case connected(MenuClientID)
    /// A message arrived from a Pressing Menu.
    case received(Data, from: MenuClientID)
    /// A Pressing Menu went away.
    case disconnected(MenuClientID)
}

/// Port: the phone's side of the link to Pressing Menus. The core builds
/// and encodes every message; the adapter only moves them. Production: a
/// WebSocket listener advertised over Bonjour as `_pressing._tcp` (ADR-0004).
@MainActor
public protocol MenuServer: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void)
    /// Starts listening and advertising. Several Pressing Menus may connect.
    func start()
    func stop()
    /// Sends one message to one Pressing Menu.
    func send(_ message: Data, to client: MenuClientID)
}
