import Foundation
import Observation

/// The headless core. The app renders `state` and forwards intents.
@MainActor
@Observable
public final class Pressing {
    public internal(set) var state = PressingState()
    /// Every Play kept on the phone, newest first, the current one included.
    /// Apart from `state` so the level meter's updates don't redraw History.
    public internal(set) var history: [Play] = []

    /// Recently played, as Now Playing lists it under the current Track:
    /// History, newest first, without the current Play.
    public var recentPlays: [Play] {
        guard let current = state.play else { return history }
        return history.filter { $0.id != current.id }
    }
    @ObservationIgnored let artwork: any ArtworkDownloader

    @ObservationIgnored private let audioInput: any AudioInput
    @ObservationIgnored let store: any Store
    @ObservationIgnored let streamSink: any StreamSink
    @ObservationIgnored let scheduler: any Scheduler
    @ObservationIgnored let sonos: any SonosNetwork
    @ObservationIgnored private let encoder: any MP3Encoder
    @ObservationIgnored var detector: Detector!
    @ObservationIgnored var identifier: Identifier!
    @ObservationIgnored let stream: StreamServer
    @ObservationIgnored private var resampler: Resampler?
    /// Where each Room's player answers SOAP, by RINCON id.
    @ObservationIgnored var roomHosts: [RoomState.ID: String] = [:]
    /// A topology read is under way, so further players found join it.
    @ObservationIgnored var isReadingTopology = false
    /// The Rooms Pressing holds, and how it watches them.
    @ObservationIgnored var hold = Hold()
    /// The last Sonos command queued; the next waits for it.
    @ObservationIgnored var sonosQueue: Task<Void, Never>?
    @ObservationIgnored let lastFmPorts: LastFmPorts
    /// The Plays owed to Last.fm and how they are being sent.
    @ObservationIgnored var scrobbling = Scrobbling()

    /// The port the stream is served on. Fixed, so Pressing recognises its
    /// own stream in a Room whatever the phone's IP address is now.
    public static let streamPort: UInt16 = 8020
    /// The stream's path. Distinctive, so no other app's radio URL matches it.
    public static let streamPath = "/pressing/turntable.mp3"

    public init(
        audioInput: any AudioInput,
        store: any Store,
        scheduler: any Scheduler,
        sonos: any SonosNetwork,
        streamSink: any StreamSink,
        encoder: any MP3Encoder,
        recognizer: any Recognizer,
        artwork: any ArtworkDownloader,
        lastFm: LastFmPorts
    ) {
        self.audioInput = audioInput
        lastFmPorts = lastFm
        self.artwork = artwork
        self.store = store
        self.scheduler = scheduler
        self.sonos = sonos
        self.streamSink = streamSink
        self.encoder = encoder
        stream = StreamServer(sink: streamSink, path: Self.streamPath)
        detector = Detector(scheduler: scheduler) { [weak self] event in
            self?.handle(event)
        }
        identifier = Identifier(recognizer: recognizer, scheduler: scheduler) { [weak self] event in
            self?.handle(event)
        }
    }

    /// Call once at launch. Until an input is chosen, only the screen,
    /// History and Last.fm start.
    public func start() {
        settings = store.loadSettings() ?? Settings()
        loadHistory()
        startLastFm()
        applyDetection()
        state.screen.blankAfter = settings.blankAfter
        wakeScreen()
        state.input.chosenID = settings.inputID
        state.input.chosenName = settings.inputName
        state.input.available = audioInput.availableInputs
        audioInput.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        // Before an input is chosen, nothing starts: the first launch asks
        // one thing at a time, and the local network prompt waits.
        if settings.inputID != nil { startServices() }
        startCapture()
    }

    @ObservationIgnored private var servicesStarted = false

    /// The stream server and Sonos discovery. Once started they keep running,
    /// even when the input disappears, so Rooms stay known.
    private func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        stream.start(port: Self.streamPort)
        startDiscovery()
    }

    private func handle(_ event: AudioInputEvent) {
        switch event {
        case .buffer(let buffer):
            receive(buffer)
        case .routeChanged:
            state.input.available = audioInput.availableInputs
            startCapture()
        case .interruptionBegan:
            state.input.status = .interrupted
            clearLevel()
        case .interruptionEnded, .mediaServicesReset:
            startCapture()
        }
    }

    /// Intent from Settings: capture from this input from now on.
    public func chooseInput(_ id: AudioInputDevice.ID) {
        settings.inputID = id
        store.saveSettings(settings)
        state.input.chosenID = id
        noiseFloor = NoiseFloor(threshold: settings.detection.threshold)
        state.input.noiseFloor = nil
        startServices()
        startCapture()
    }

    /// Intent from Settings: calibrate detection. Refuses a stop delay that
    /// isn't longer than the Flip threshold, so a Session can't end before
    /// the Record it contains. Takes effect from the next change in level.
    public func setDetection(_ detection: DetectionSettings) throws(DetectionSettingsError) {
        guard detection.stopDelay > detection.flipThreshold else {
            throw .stopDelayNotLongerThanFlipThreshold
        }
        settings.detection = detection
        store.saveSettings(settings)
        applyDetection()
    }

    /// Intent from Settings: blank the screen after this long, or never.
    public func setBlankAfter(_ blankAfter: BlankAfter) {
        settings.blankAfter = blankAfter
        store.saveSettings(settings)
        state.screen.blankAfter = blankAfter
        wakeScreen()
    }

    /// Any touch on the screen. Returns true when the touch only woke a blank
    /// screen, so the app must not pass it on to a control.
    @discardableResult
    public func screenTouched() -> Bool {
        let wasBlanked = state.screen.isBlanked
        wakeScreen()
        return wasBlanked
    }

    /// The app came to the foreground. Wakes the screen and restarts the
    /// blank-after time, as a touch does, but there is no touch to swallow.
    public func cameToForeground() {
        wakeScreen()
    }

    @ObservationIgnored private var blankTimer: (any ScheduledWork)?

    /// Wakes the screen and starts the blank-after time again. The time only
    /// runs while no Record is playing: the screen never blanks during one.
    func wakeScreen() {
        state.screen.isBlanked = false
        blankTimer?.cancel()
        blankTimer = nil
        guard !isRecordPlaying, case .after(let seconds) = settings.blankAfter else { return }
        blankTimer = scheduler.schedule(after: seconds) { [weak self] in
            self?.state.screen.isBlanked = true
        }
    }

    private func applyDetection() {
        state.detection = settings.detection
        detector.settings = settings.detection
        noiseFloor.threshold = settings.detection.threshold
    }

    @ObservationIgnored var settings = Settings()
    @ObservationIgnored private var meter = LevelMeter()
    @ObservationIgnored private var window = LevelWindow()
    @ObservationIgnored private var noiseFloor = NoiseFloor(threshold: DetectionSettings().threshold)

    private func receive(_ buffer: PCMBuffer) {
        // Only the chosen input counts, whatever the system routed to.
        guard isCapturing, buffer.inputID == settings.inputID else { return }
        guard InputState.supportedSampleRates.contains(buffer.sampleRate) else {
            state.input.status = .unsupportedSampleRate(buffer.sampleRate)
            clearLevel()
            return
        }
        state.input.status = .present
        for frame in meter.add(buffer) {
            let level = window.add(frame)
            state.input.level = level
            state.input.noiseFloor = noiseFloor.add(level)
            detector.level(level)
        }
        if case .running(_, .playing) = state.session {
            identifier.add(buffer)
        }
        encode(buffer)
    }

    /// Everything captured is encoded, Session or not, so the pre-roll already
    /// holds the needle drop when a Session starts.
    private func encode(_ buffer: PCMBuffer) {
        if resampler?.inputRate != buffer.sampleRate {
            resampler = Resampler(inputRate: buffer.sampleRate)
        }
        let audio = resampler!.process(left: buffer.left, right: buffer.right)
        stream.send(encoder.encode(left: audio.left, right: audio.right))
    }

    private func handle(_ event: Detector.Event) {
        switch event {
        case .recordStarted:
            switch state.session {
            case .idle:
                state.session = .running(records: 1, record: .playing)
                takeOverRooms()
            case .running(let records, _):
                state.session = .running(records: records + 1, record: .playing)
            }
            // The level had to stay up for the start delay: the music began then.
            identifier.recordStarted(at: scheduler.now.addingTimeInterval(-settings.detection.startDelay))
            wakeScreen()
        case .sessionEnded:
            state.session = .idle
            stopRooms()
        case .gap:
            setRecord(.gap)
            identifier.gap(silenceBegan: scheduler.now.addingTimeInterval(-Detector.gapSeconds))
        case .resumed:
            setRecord(.playing)
        case .flip:
            setRecord(.flipped)
            identifier.flip(silenceBegan: scheduler.now.addingTimeInterval(-settings.detection.flipThreshold))
            // No Record is playing any more: the blank-after time starts.
            wakeScreen()
        }
    }

    private func setRecord(_ record: RecordState) {
        guard case .running(let records, _) = state.session else { return }
        state.session = .running(records: records, record: record)
    }

    /// A Record is playing, in a Gap or not.
    private var isRecordPlaying: Bool {
        switch state.session {
        case .running(_, .playing), .running(_, .gap): true
        default: false
        }
    }

    /// Capture was started from the chosen input and nothing has stopped it since.
    private var isCapturing: Bool {
        switch state.input.status {
        case .present, .unsupportedSampleRate: true
        default: false
        }
    }

    private func clearLevel() {
        meter.reset()
        window.reset()
        state.input.level = nil
        // No audio is silence, so an input that disappears can still flip the
        // Record and end the Session.
        detector.level(InputState.minimumLevel)
    }

    private func startCapture() {
        clearLevel()
        guard let chosen = settings.inputID else {
            state.input.status = .notChosen
            return
        }
        // Never fall back: if the chosen input isn't there, capture nothing.
        guard let device = state.input.available.first(where: { $0.id == chosen }) else {
            audioInput.stop()
            state.input.status = .missing
            return
        }
        rememberName(of: device)
        do {
            try audioInput.start(inputID: chosen)
            state.input.status = .present
        } catch AudioInputError.permissionDenied {
            state.input.status = .permissionDenied
        } catch AudioInputError.inputUnavailable {
            state.input.status = .missing
        } catch AudioInputError.failed(let reason) {
            state.input.status = .failed(reason)
        } catch {
            state.input.status = .failed("\(error)")
        }
    }

    /// Keeps the chosen input's name, so it can be named while it isn't connected.
    private func rememberName(of device: AudioInputDevice) {
        state.input.chosenName = device.name
        guard settings.inputName != device.name else { return }
        settings.inputName = device.name
        store.saveSettings(settings)
    }
}
