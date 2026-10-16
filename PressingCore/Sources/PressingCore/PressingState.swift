import Foundation

/// The one snapshot the app renders.
public struct PressingState: Sendable, Equatable {
    public var input: InputState
    public var session: SessionState
    /// The Sonos Rooms found on the network, by name.
    public var rooms: [RoomState]
    /// The detection calibration in force, as set in Settings.
    public var detection: DetectionSettings
    public var screen: ScreenState
    /// The current Play, whose Track fills Now Playing. Nil when nothing
    /// is identified: Now Playing keeps the Track's space empty.
    public var play: Play?
    public var lastFm: LastFmState

    public init(
        input: InputState = InputState(),
        session: SessionState = .idle,
        rooms: [RoomState] = [],
        detection: DetectionSettings = DetectionSettings(),
        screen: ScreenState = ScreenState(),
        play: Play? = nil,
        lastFm: LastFmState = LastFmState()
    ) {
        self.input = input
        self.session = session
        self.rooms = rooms
        self.detection = detection
        self.screen = screen
        self.play = play
        self.lastFm = lastFm
    }

    /// The page the app shows, following the Session and the input.
    /// A running Session wins over a missing input: the Session ends by
    /// itself once the silence reaches the stop delay.
    public var page: Page {
        if case .running = session { return .nowPlaying }
        if input.chosenID == nil { return .chooseInput(.noneChosen) }
        if input.status == .missing { return .chooseInput(.notConnected) }
        return .waiting
    }
}

/// The app's root page. Which one shows is decided here, not in the app.
public enum Page: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// No input has ever been chosen.
        case noneChosen
        /// The chosen input isn't connected.
        case notConnected
    }

    /// Pressing needs an input before anything else.
    case chooseInput(Reason)
    /// The input is ready and no Session is running.
    case waiting
    /// A Session is running: the current Track shows.
    case nowPlaying
}

/// Whether Plays go to Last.fm, as Settings shows it.
public struct LastFmState: Sendable, Equatable {
    public enum Connection: Sendable, Equatable {
        /// The build has no Last.fm API key and secret.
        case unavailable
        /// Plays aren't sent. Those made now are never sent later.
        case disconnected
        /// The sign-in is under way.
        case connecting
        /// Plays go to this listener's Last.fm profile.
        case connected(username: String)
    }

    /// Something the listener should know about.
    public enum Problem: Sendable, Equatable {
        /// Signing in failed: Last.fm couldn't be reached or refused.
        case signInFailed
        /// Last.fm no longer accepts the session, most likely revoked from
        /// the listener's Last.fm settings. Plays already owed stay queued
        /// until Last.fm is connected again.
        case sessionRevoked
        /// Last.fm refuses Pressing's API key or signature (its error code).
        /// The build configuration needs fixing; Plays wait for Last.fm meanwhile.
        case misconfigured(code: Int)
    }

    public var connection: Connection
    public var problem: Problem?

    public init(connection: Connection = .disconnected, problem: Problem? = nil) {
        self.connection = connection
        self.problem = problem
    }
}

/// The screen blanker. Blanking is Pressing's own: the app keeps the system
/// idle timer disabled and covers the screen in black while `isBlanked`.
/// It never blanks while a Record is playing, Gaps included.
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
    /// starts before the silence reaches the stop delay.
    case flipped
}

/// A Sonos Room as the Rooms sheet lists it.
public struct RoomState: Sendable, Equatable, Identifiable {
    /// The RINCON id of the Room's visible player.
    public var id: String
    /// The Room's name, as the Sonos app shows it.
    public var name: String
    /// Switched on in Pressing: a Session takes it over.
    public var isOn: Bool
    /// The volume Pressing sets when it takes the Room over, 0 to 100.
    public var volume: Int
    /// False once the Room stopped answering, until it answers again.
    public var isReachable: Bool
    /// Someone took the Room over from the Sonos app, so Pressing leaves it
    /// alone until the next Session or until it is switched off and on.
    public var isSteppedBack: Bool

    public init(id: String, name: String, isOn: Bool, volume: Int, isReachable: Bool = true, isSteppedBack: Bool = false) {
        self.id = id
        self.name = name
        self.isOn = isOn
        self.volume = volume
        self.isReachable = isReachable
        self.isSteppedBack = isSteppedBack
    }
}
