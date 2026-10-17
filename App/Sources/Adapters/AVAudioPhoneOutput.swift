import AVFoundation
import FirstPressCore

/// Production PhoneOutput: plays the captured audio through whatever the phone
/// outputs to (its speaker, earphones or an AirPlay receiver, as chosen with
/// the system route picker), at the system volume.
///
/// The audio session belongs to the capture adapter: switching the Phone
/// output on or off asks it to change category, and it keeps capturing from
/// the chosen input. This adapter has its own engine that only plays, and
/// never touches an input node, so it can't bind to any input.
@MainActor
final class AVAudioPhoneOutput: PhoneOutput {
    /// Buffers held before playing starts, so the next one is always due
    /// before the last runs out. A tap buffer is about 0.1 s.
    private static let primedBuffers = 2
    /// Beyond this many buffers waiting (about a second), new audio is
    /// dropped rather than letting the delay grow.
    private static let maximumQueued = 10

    private let input: AVAudioSessionInput
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var isStarted = false
    /// Buffers scheduled on the current player and not yet played.
    private var queued = 0
    /// Counts players, so a finished buffer is only counted against its own.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    init(input: AVAudioSessionInput) {
        self.input = input
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            // The old engine is dead; drop it without touching it. The next
            // buffer builds a new one.
            MainActor.assumeIsolated {
                self?.forgetEngine()
                self?.reportRoute()
            }
        })
    }

    private var routeHandler: (@MainActor (PhoneOutputRoute?) -> Void)?

    func setRouteHandler(_ handler: @escaping @MainActor (PhoneOutputRoute?) -> Void) {
        routeHandler = handler
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportRoute() }
            }
        }
        reportRoute()
    }

    private var routeObserver: NSObjectProtocol?

    /// The system's current output, as the core names it. Only reads the
    /// route; choosing one is the system picker's job.
    private func reportRoute() {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            routeHandler?(nil)
            return
        }
        let kind: PhoneOutputRoute.Kind = switch output.portType {
        case .builtInSpeaker, .builtInReceiver: .builtInSpeaker
        case .headphones, .lineOut, .usbAudio, .HDMI: .wired
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: .bluetooth
        case .airPlay: .airPlay
        default: .other
        }
        routeHandler?(PhoneOutputRoute(name: output.portName, kind: kind))
    }

    func switched(on: Bool) {
        input.setPlaybackAllowed(on)
    }

    func start() {
        isStarted = true
    }

    func stop() {
        isStarted = false
        tearDown()
    }

    func play(_ buffer: PCMBuffer) {
        guard isStarted, buffer.frameCount > 0 else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: buffer.sampleRate, channels: 2)!
        guard let player = player(for: format), queued < Self.maximumQueued,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.frameCount)),
              let channels = pcm.floatChannelData
        else { return }
        pcm.frameLength = AVAudioFrameCount(buffer.frameCount)
        buffer.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: buffer.frameCount) }
        buffer.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: buffer.frameCount) }

        queued += 1
        let generation = generation
        player.scheduleBuffer(pcm) { [weak self] in
            Task { @MainActor in self?.played(generation) }
        }
        if !player.isPlaying, queued >= Self.primedBuffers {
            player.play()
        }
    }

    // MARK: - Private

    /// A running player for audio in this format, built afresh when the format
    /// changes or the engine stopped (an interruption, or the output's
    /// hardware changed when another route was chosen).
    private func player(for format: AVAudioFormat) -> AVAudioPlayerNode? {
        if let engine, let player, engine.isRunning, self.format == format {
            return player
        }
        tearDown()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        // The mixer converts to whatever the output runs at.
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            return nil
        }
        self.engine = engine
        self.player = player
        self.format = format
        return player
    }

    private func played(_ generation: Int) {
        guard generation == self.generation, queued > 0 else { return }
        queued -= 1
    }

    private func tearDown() {
        player?.stop()
        engine?.stop()
        forgetEngine()
    }

    private func forgetEngine() {
        engine = nil
        player = nil
        format = nil
        queued = 0
        generation += 1
    }
}
