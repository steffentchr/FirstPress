import Foundation

/// What the listener has set in Settings.
public struct Settings: Sendable, Equatable, Codable {
    /// The input chosen in Settings. Nil until the listener chooses one; Pressing
    /// never picks one on its own.
    public var inputID: AudioInputDevice.ID?
    /// How Records and Sessions are detected.
    public var detection: DetectionSettings
    /// How long the screen stays on once no Record is playing.
    public var blankAfter: BlankAfter
    /// The listener's choice for each Room they have touched, by RINCON id.
    public var rooms: [String: RoomChoice]

    public init(
        inputID: AudioInputDevice.ID? = nil,
        detection: DetectionSettings = DetectionSettings(),
        blankAfter: BlankAfter = .default,
        rooms: [String: RoomChoice] = [:]
    ) {
        self.inputID = inputID
        self.detection = detection
        self.blankAfter = blankAfter
        self.rooms = rooms
    }

    // Settings saved before a field existed decode with that field's default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputID = try container.decodeIfPresent(AudioInputDevice.ID.self, forKey: .inputID)
        detection = try container.decodeIfPresent(DetectionSettings.self, forKey: .detection) ?? DetectionSettings()
        blankAfter = try container.decodeIfPresent(BlankAfter.self, forKey: .blankAfter) ?? .default
        rooms = try container.decodeIfPresent([String: RoomChoice].self, forKey: .rooms) ?? [:]
    }
}

/// Whether a Room is switched on in Pressing, and its volume.
public struct RoomChoice: Sendable, Equatable, Codable {
    public var isOn: Bool
    /// 0 to 100.
    public var volume: Int

    /// A Room seen for the first time is off, at a moderate volume.
    public static let `default` = RoomChoice(isOn: false, volume: 25)

    public init(isOn: Bool, volume: Int) {
        self.isOn = isOn
        self.volume = volume
    }
}

/// When the screen blanks to protect the OLED panel.
public enum BlankAfter: Sendable, Hashable, Codable {
    case never
    /// Seconds of silence with no Record playing, restarted by a touch.
    case after(TimeInterval)

    public static let `default` = BlankAfter.after(5 * 60)
}

/// The calibration for Record and Session detection.
public struct DetectionSettings: Sendable, Equatable, Codable {
    /// Level in dBFS above which the deck counts as playing. Set it clearly
    /// above the noise floor and below the quietest music.
    public var threshold: Double
    /// Seconds the level must stay above the threshold to start a Record.
    public var startDelay: TimeInterval
    /// Seconds of silence that end a Record with a Flip.
    public var flipThreshold: TimeInterval
    /// Seconds of silence, counted from when it began, that end the Session
    /// unless a new Record starts. Must be longer than the Flip threshold.
    public var stopDelay: TimeInterval

    public init(threshold: Double = -50, startDelay: TimeInterval = 1.5, flipThreshold: TimeInterval = 12, stopDelay: TimeInterval = 45) {
        self.threshold = threshold
        self.startDelay = startDelay
        self.flipThreshold = flipThreshold
        self.stopDelay = stopDelay
    }
}

public enum DetectionSettingsError: Error, Sendable, Equatable {
    /// A Session could end before the Record it contains.
    case stopDelayNotLongerThanFlipThreshold
}

/// Port: durable storage on the phone.
///
/// Settings include Room choices and volumes. Plays are kept indefinitely.
/// A later ticket adds the scrobble queue.
/// Credentials do not go here; they go in the Keychain.
@MainActor
public protocol Store: AnyObject {
    func loadSettings() -> Settings?
    func saveSettings(_ settings: Settings)
    /// Keeps a Play, replacing the one kept with the same id.
    func savePlay(_ play: Play)
    /// Every Play kept, in any order.
    func loadPlays() -> [Play]
}
