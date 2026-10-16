import Foundation

/// What the listener has set in Settings.
public struct Settings: Sendable, Equatable, Codable {
    /// The input chosen in Settings. Nil until the listener chooses one; Pressing
    /// never picks one on its own.
    public var inputID: AudioInputDevice.ID?

    public init(inputID: AudioInputDevice.ID? = nil) {
        self.inputID = inputID
    }
}

/// Port: durable storage on the phone.
///
/// Later tickets add Room choices and volumes, Plays and the scrobble queue.
/// Credentials do not go here; they go in the Keychain.
@MainActor
public protocol Store: AnyObject {
    func loadSettings() -> Settings?
    func saveSettings(_ settings: Settings)
}
