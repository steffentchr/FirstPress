import Foundation

/// The one snapshot the app renders.
public struct FirstPressState: Sendable, Equatable {
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
    /// The iPhone's own output, as the Rooms sheet shows it.
    public var phoneOutput = PhoneOutputState()

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
    /// Now Playing's gear and speaker icons are hidden: kiosk mode, and no
    /// touch for 30 s. A touch brings them back.
    public var hidesControls: Bool {
        screen.isKiosk && page == .nowPlaying && screen.controlsIdle
    }

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

    /// First Press needs an input before anything else.
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
        /// Last.fm refuses First Press's API key or signature (its error code).
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

/// The screen blanker. Blanking is First Press's own: the app keeps the system
/// idle timer disabled and covers the screen in black while `isBlanked`.
/// It never blanks while a Record is playing, Gaps included.
public struct ScreenState: Sendable, Equatable {
    public var isBlanked: Bool
    /// As set in Settings.
    public var blankAfter: BlankAfter
    /// Kiosk mode, as set in Settings: the app takes the whole screen.
    public var isKiosk: Bool
    /// As set in Settings.
    public var appearance: Appearance = .default
    /// No touch for a while: in kiosk mode, Now Playing hides its icons.
    public var controlsIdle = false

    public init(isBlanked: Bool = false, blankAfter: BlankAfter = .default, isKiosk: Bool = false) {
        self.isBlanked = isBlanked
        self.blankAfter = blankAfter
        self.isKiosk = isKiosk
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
        /// The chosen input runs at a rate First Press does not take (only 44.1 and 48 kHz).
        case unsupportedSampleRate(Double)
        /// Capture could not start for another reason.
        case failed(String)
    }

    /// The bottom of the meter. Digital silence reads as this, not minus infinity.
    public static let minimumLevel: Double = -100

    /// Sample rates First Press takes from an input.
    public static let supportedSampleRates: Set<Double> = [44_100, 48_000]

    public var status: Status
    /// Inputs to offer in Settings.
    public var available: [AudioInputDevice]
    /// The input chosen in Settings.
    public var chosenID: AudioInputDevice.ID?
    /// The chosen input's name, kept while it isn't connected. Nil when none
    /// is chosen, or when it hasn't been seen since it was chosen.
    public var chosenName: String?
    /// Live level in dBFS, nil while nothing is being captured.
    public var level: Double?
    /// Level during silence (below the start threshold) in dBFS, nil until measured.
    public var noiseFloor: Double?

    public init(
        status: Status = .notChosen,
        available: [AudioInputDevice] = [],
        chosenID: AudioInputDevice.ID? = nil,
        chosenName: String? = nil,
        level: Double? = nil,
        noiseFloor: Double? = nil
    ) {
        self.status = status
        self.available = available
        self.chosenID = chosenID
        self.chosenName = chosenName
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

/// The Phone output: "This iPhone" in the Rooms sheet.
public struct PhoneOutputState: Sendable, Equatable {
    /// Switched on: the Record plays on the phone while a Session runs.
    public var isOn: Bool
    /// Where the phone plays now, as the system routes it. Nil until the
    /// Phone output reports one, or while the system routes to no output.
    public var route: PhoneOutputRoute?

    public init(isOn: Bool = false, route: PhoneOutputRoute? = nil) {
        self.isOn = isOn
        self.route = route
    }
}

/// Where the phone's audio goes: chosen on the phone, with the system's
/// route picker or by plugging something in.
public struct PhoneOutputRoute: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The phone's own speaker.
        case builtInSpeaker
        /// Earphones or another output on a cable.
        case wired
        case bluetooth
        case airPlay
        /// Anything else the system routes to.
        case other

        public init(from decoder: any Decoder) throws {
            // A kind added later reads as other.
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }
    }

    /// The output's name as the system gives it, such as "Kitchen" for an
    /// AirPlay receiver or "AirPods".
    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Where This iPhone plays, as the Rooms sheet and First Press Menu say
    /// it: "AirPlay: Kitchen", "iPhone speaker" or "AirPods".
    public var label: String {
        switch kind {
        case .builtInSpeaker: "iPhone speaker"
        case .airPlay: "AirPlay: \(name)"
        case .wired, .bluetooth, .other: name
        }
    }
}

/// A Sonos Room as the Rooms sheet lists it.
public struct RoomState: Sendable, Equatable, Identifiable {
    /// The RINCON id of the Room's visible player.
    public var id: String
    /// The Room's name, as the Sonos app shows it.
    public var name: String
    /// Switched on in First Press: a Session takes it over.
    public var isOn: Bool
    /// The volume First Press sets when it takes the Room over, 0 to 100.
    public var volume: Int
    /// False once the Room stopped answering, until it answers again.
    public var isReachable: Bool
    /// Someone took the Room over from the Sonos app, so First Press leaves it
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
