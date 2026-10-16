import Foundation
import Observation

/// The headless core. The app renders `state` and forwards intents.
@MainActor
@Observable
public final class Pressing {
    public private(set) var state = PressingState()

    @ObservationIgnored private let audioInput: any AudioInput
    @ObservationIgnored private let store: any Store
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var detector: Detector!

    public init(audioInput: any AudioInput, store: any Store, scheduler: any Scheduler) {
        self.audioInput = audioInput
        self.store = store
        self.scheduler = scheduler
        detector = Detector(scheduler: scheduler) { [weak self] event in
            self?.handle(event)
        }
    }

    /// Call once at launch.
    public func start() {
        settings = store.loadSettings() ?? Settings()
        applyDetection()
        state.screen.blankAfter = settings.blankAfter
        wakeScreen()
        state.input.chosenID = settings.inputID
        state.input.available = audioInput.availableInputs
        audioInput.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        startCapture()
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

    @ObservationIgnored private var blankTimer: (any ScheduledWork)?

    /// Wakes the screen and starts the blank-after time again. The time only
    /// runs while no Record is playing: the screen never blanks during one.
    private func wakeScreen() {
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

    @ObservationIgnored private var settings = Settings()
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
    }

    private func handle(_ event: Detector.Event) {
        switch event {
        case .recordStarted:
            switch state.session {
            case .idle:
                state.session = .running(records: 1, record: .playing)
            case .running(let records, _):
                state.session = .running(records: records + 1, record: .playing)
            }
            wakeScreen()
        case .sessionEnded:
            state.session = .idle
        case .gap:
            setRecord(.gap)
        case .resumed:
            setRecord(.playing)
        case .flip:
            setRecord(.flipped)
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
        guard state.input.available.contains(where: { $0.id == chosen }) else {
            audioInput.stop()
            state.input.status = .missing
            return
        }
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
}
