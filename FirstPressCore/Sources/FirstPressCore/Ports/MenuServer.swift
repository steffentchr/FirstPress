import Foundation

/// One First Press Menu's connection to the phone.
public struct MenuConnectionID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public enum MenuServerEvent: Sendable, Equatable {
    /// A First Press Menu connected.
    case connected(MenuConnectionID)
    /// A message arrived from a First Press Menu.
    case received(Data, from: MenuConnectionID)
    /// A First Press Menu went away.
    case disconnected(MenuConnectionID)
}

/// Port: the phone's side of the link to First Press Menus. The core builds
/// and encodes every message; the adapter only moves them. Production: a
/// WebSocket listener advertised over Bonjour as `_firstpress._tcp` (ADR-0004).
@MainActor
public protocol MenuServer: AnyObject {
    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void)
    /// Starts listening and advertising. Several First Press Menus may connect.
    func start()
    func stop()
    /// Sends one message to one First Press Menu.
    func send(_ message: Data, to connection: MenuConnectionID)
}
