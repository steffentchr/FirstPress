import AVFoundation
import FirstPressCore

/// Production AudioInput: AVAudioSession in `.record` / `.measurement` (no AGC,
/// no voice processing) with the chosen input selected explicitly.
///
/// While the Phone output is switched on, the session is `.playAndRecord`
/// instead, still in `.measurement` and still on the chosen input, so the
/// phone can play while it captures. Bluetooth is allowed only as an output
/// (A2DP), never as a headset microphone (HFP), and AirPlay is allowed.
///
/// It never captures from anything but the input passed to `start(inputID:)`.
/// When a device comes or goes, or the route ends up on another input, it stops
/// capture before telling the core, so a fallback to the built-in mic is never
/// heard; the core decides whether to start again.
@MainActor
final class AVAudioSessionInput: AudioInput {
    private let session = AVAudioSession.sharedInstance()
    private var engine: AVAudioEngine?
    private var chosenID: AudioInputDevice.ID?
    private var handler: (@MainActor (AudioInputEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// The Phone output is switched on, so the session must be able to play.
    private var allowsPlayback = false
    private var engineObserver: NSObjectProtocol?

    init() {
        // availableInputs is only filled in once the category can record.
        try? session.setCategory(.record, mode: .measurement, options: [])
        observeSession()
    }

    var availableInputs: [AudioInputDevice] {
        (session.availableInputs ?? []).map(Self.device)
    }

    func setEventHandler(_ handler: @escaping @MainActor (AudioInputEvent) -> Void) {
        self.handler = handler
    }

    /// The listener refused microphone access, so the inputs can't be listed.
    var isPermissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Asks for microphone access if it hasn't been asked yet, since listing
    /// the inputs needs it. Called from the choose-input screen, so the first
    /// launch asks for nothing before then. Once answered, the core reads the
    /// inputs again through the usual route-change path.
    func requestPermission() async {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        _ = await AVAudioApplication.requestRecordPermission()
        handler?(.routeChanged)
    }

    /// Called by the Phone output when it is switched on or off. The category
    /// only changes with capture stopped, so a running capture restarts at
    /// once, from the same input. Not capturing, the next start applies it.
    func setPlaybackAllowed(_ allowed: Bool) {
        guard allowed != allowsPlayback else { return }
        allowsPlayback = allowed
        guard engine != nil, let chosenID else { return }
        do {
            try start(inputID: chosenID)
        } catch {
            // Let the core decide, as for any other lost input.
            stopEngine()
            handler?(.routeChanged)
        }
    }

    func start(inputID: AudioInputDevice.ID) throws {
        stopEngine()
        chosenID = inputID

        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            throw AudioInputError.permissionDenied
        case .undetermined:
            // Ask, then let the core try again through the usual route-change path.
            AVAudioApplication.requestRecordPermission { @Sendable [weak self] _ in
                Task { @MainActor in self?.handler?(.routeChanged) }
            }
            throw AudioInputError.failed("Waiting for microphone permission")
        case .granted:
            break
        @unknown default:
            break
        }

        do {
            try setCategory()
            try session.setActive(true)
            guard let port = session.availableInputs?.first(where: { $0.uid == inputID }) else {
                throw AudioInputError.inputUnavailable
            }
            try session.setPreferredInput(port)
        } catch let error as AudioInputError {
            throw error
        } catch {
            throw AudioInputError.failed(error.localizedDescription)
        }
        guard session.currentRoute.inputs.first?.uid == inputID else {
            throw AudioInputError.inputUnavailable
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioInputError.inputUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tap(inputID: inputID) { @Sendable [weak self] buffer in
            Task { @MainActor in self?.handler?(.buffer(buffer)) }
        })
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioInputError.failed(error.localizedDescription)
        }
        self.engine = engine
        observeConfigurationChange(of: engine)
    }

    func stop() {
        stopEngine()
        chosenID = nil
    }

    // MARK: - Private

    /// Capture alone records; with the Phone output on it also plays, with
    /// the speaker rather than the earpiece when nothing else is connected.
    /// `.allowBluetoothHFP` stays off, so a headset never becomes the input.
    private func setCategory() throws {
        if allowsPlayback {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker])
        } else {
            try session.setCategory(.record, mode: .measurement, options: [])
        }
    }

    /// With the Phone output on, choosing another output (earphones, AirPlay)
    /// can change the hardware's sample rate, and the engine then stops itself
    /// without a route change that names a device. Treat that like a route
    /// change so the core starts capture again from the chosen input. Only
    /// while playback is allowed: with the Phone output off, capture behaves
    /// exactly as before.
    private func observeConfigurationChange(of engine: AVAudioEngine) {
        let id = ObjectIdentifier(engine)
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Not torn down inside the notification itself: that can deadlock.
            Task { @MainActor in self?.engineStoppedItself(id) }
        }
    }

    private func engineStoppedItself(_ id: ObjectIdentifier) {
        guard allowsPlayback, let engine, ObjectIdentifier(engine) == id else { return }
        stopEngine()
        handler?(.routeChanged)
    }

    private func stopEngine() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Runs on the audio thread: copies the samples out and hands them on.
    private nonisolated static func tap(
        inputID: AudioInputDevice.ID,
        deliver: @escaping @Sendable (PCMBuffer) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            guard let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = (0..<Int(buffer.format.channelCount)).map { channel in
                Array(UnsafeBufferPointer(start: data[channel], count: frames))
            }
            deliver(PCMBuffer(
                inputID: inputID,
                sampleRate: buffer.format.sampleRate,
                time: AVAudioTime.seconds(forHostTime: time.hostTime),
                channels: channels
            ))
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated { self.routeChanged(reason: reason) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated { self.interrupted(type: type) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated { self.mediaServicesReset() }
        })
    }

    private func routeChanged(reason: AVAudioSession.RouteChangeReason?) {
        let deviceCameOrWent = reason == .newDeviceAvailable || reason == .oldDeviceUnavailable
        let onWrongInput = engine != nil && session.currentRoute.inputs.first?.uid != chosenID
        // Our own setPreferredInput also changes the route; ignore that, or we'd loop.
        // So is the category change when the Phone output is switched: capture
        // has already restarted on the chosen input by the time it arrives.
        guard deviceCameOrWent || onWrongInput else { return }
        stopEngine()
        handler?(.routeChanged)
    }

    private func interrupted(type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            stopEngine()
            handler?(.interruptionBegan)
        case .ended:
            handler?(.interruptionEnded)
        default:
            break
        }
    }

    private func mediaServicesReset() {
        // The old engine is dead; drop it without touching it.
        engine = nil
        handler?(.mediaServicesReset)
    }

    private static func device(_ port: AVAudioSessionPortDescription) -> AudioInputDevice {
        let kind: AudioInputDevice.Kind = switch port.portType {
        case .usbAudio: .usb
        case .builtInMic: .builtInMic
        default: .other
        }
        return AudioInputDevice(id: port.uid, name: port.portName, kind: kind)
    }
}
