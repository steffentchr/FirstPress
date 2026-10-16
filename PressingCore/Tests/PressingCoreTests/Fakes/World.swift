import Foundation
import PressingCore

extension Pressing {
    /// For tests that only care about the input: every other port is a fake
    /// nobody looks at.
    convenience init(audioInput: any AudioInput, store: any Store, scheduler: any Scheduler) {
        self.init(
            audioInput: audioInput,
            store: store,
            scheduler: scheduler,
            sonos: FakeSonosNetwork(),
            streamSink: FakeStreamSink(),
            encoder: PassThroughEncoder(),
            recognizer: FakeRecognizer()
        )
    }
}

/// Pressing wired to a fake of every port, with the deck chosen and plugged in.
@MainActor
struct World {
    let input = FakeAudioInput(availableInputs: [.deck])
    let scheduler = FakeScheduler()
    let store: FakeStore
    let sonos: FakeSonos
    let sink = FakeStreamSink()
    let encoder = PassThroughEncoder()
    let recognizer = FakeRecognizer()
    let pressing: Pressing

    init(settings: Settings = Settings(inputID: AudioInputDevice.deck.id), sonos: FakeSonos = FakeSonos()) {
        store = FakeStore(settings: settings)
        self.sonos = sonos
        pressing = Pressing(
            audioInput: input,
            store: store,
            scheduler: scheduler,
            sonos: sonos.network,
            streamSink: sink,
            encoder: encoder,
            recognizer: recognizer
        )
        pressing.start()
    }

    /// Plays mono samples from the deck in real time.
    func play(_ samples: [Float], sampleRate: Double = 44_100) {
        input.play(samples, sampleRate: sampleRate, on: scheduler)
    }

    /// Music, well above the default threshold.
    func music(seconds: Double, sampleRate: Double = 44_100) {
        play(Signal.square(amplitude: 0.1, seconds: seconds, sampleRate: sampleRate), sampleRate: sampleRate)
    }

    /// Silence, below the default threshold.
    func silence(seconds: Double) {
        play(Signal.square(amplitude: 0.001, seconds: seconds, sampleRate: 44_100))
    }
}
