import Foundation

/// The one snapshot the app renders. Later tickets add Rooms, the lower-third
/// Track and the Last.fm connection.
public struct PressingState: Sendable, Equatable {
    public var input: InputState
    public var session: SessionState
    /// The detection calibration in force, as set in Settings.
    public var detection: DetectionSettings
    public var screen: ScreenState

    public init(
        input: InputState = InputState(),
        session: SessionState = .idle,
        detection: DetectionSettings = DetectionSettings(),
        screen: ScreenState = ScreenState()
    ) {
        self.input = input
        self.session = session
        self.detection = detection
        self.screen = screen
    }
}

/// The screen blanker. Blanking is Pressing's own: the app keeps the system
/// idle timer disabled and covers the screen in black while `isBlanked`.
public struct ScreenState: Sendable, Equatable {
    public var isBlanked: Bool
    /// As set in Settings.
    public var blankAfter: BlankAfter

    public init(isBlanked: Bool = false, blankAfter: BlankAfter = .default) {
        self.isBlanked = isBlanked
        self.blankAfter = blankAfter
    }
}

public struct InputState: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// No input has been chosen in Settings yet.
        case notChosen
        /// The chosen input is not connected.
        case missing
        /// Capturing from the chosen input.
        case present
        /// Another app or a call has the audio session for now.
        case interrupted
        /// Microphone access has not been granted.
        case permissionDenied
        /// The chosen input runs at a rate Pressing does not take (only 44.1 and 48 kHz).
        case unsupportedSampleRate(Double)
        /// Capture could not start for another reason.
        case failed(String)
    }

    /// The bottom of the meter. Digital silence reads as this, not minus infinity.
    public static let minimumLevel: Double = -100

    /// Sample rates Pressing takes from an input.
    public static let supportedSampleRates: Set<Double> = [44_100, 48_000]

    public var status: Status
    /// Inputs to offer in Settings.
    public var available: [AudioInputDevice]
    /// The input chosen in Settings.
    public var chosenID: AudioInputDevice.ID?
    /// Live level in dBFS, nil while nothing is being captured.
    public var level: Double?
    /// Level during silence (below the start threshold) in dBFS, nil until measured.
    public var noiseFloor: Double?

    public init(
        status: Status = .notChosen,
        available: [AudioInputDevice] = [],
        chosenID: AudioInputDevice.ID? = nil,
        level: Double? = nil,
        noiseFloor: Double? = nil
    ) {
        self.status = status
        self.available = available
        self.chosenID = chosenID
        self.level = level
        self.noiseFloor = noiseFloor
    }
}

/// Whether a Session is running and what its current Record is doing.
public enum SessionState: Sendable, Equatable {
    /// No Session: nothing has started since launch or the last Session ended.
    case idle
    /// A Session is running. `records` counts the Records in it so far,
    /// including the current or most recent one.
    case running(records: Int, record: RecordState)
}

public enum RecordState: Sendable, Equatable {
    /// A Record is playing.
    case playing
    /// A Record is in a Gap between two tracks.
    case gap
    /// The last Record ended with a Flip. The Session ends unless a new Record
    /// starts within the stop delay.
    case flipped
}
