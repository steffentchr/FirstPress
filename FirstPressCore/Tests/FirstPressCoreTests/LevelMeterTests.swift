import Testing
import FirstPressCore

@MainActor
@Suite("Live level")
struct LevelMeterTests {
    private func capturingDeck() -> (FakeAudioInput, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())
        firstPress.start()
        return (input, firstPress)
    }

    @Test("Level is shown in dBFS once 100 ms of audio has arrived", arguments: [44_100.0, 48_000.0])
    func levelInDBFS(sampleRate: Double) throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.5, seconds: 0.05, sampleRate: sampleRate), sampleRate: sampleRate)
        #expect(firstPress.state.input.level == nil)

        input.feed(Signal.square(amplitude: 0.5, seconds: 0.05, sampleRate: sampleRate), sampleRate: sampleRate)
        let level = try #require(firstPress.state.input.level)
        #expect(abs(level - (-6.02)) < 0.01)
    }

    @Test("Level follows the music")
    func levelFollowsMusic() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.5, seconds: 1, sampleRate: 44_100), sampleRate: 44_100)
        input.feed(Signal.square(amplitude: 0.01, seconds: 1, sampleRate: 44_100), sampleRate: 44_100)

        let level = try #require(firstPress.state.input.level)
        #expect(abs(level - (-40.0)) < 0.01)
    }

    @Test("Level is the median of the last second, so a click doesn't lift it")
    func clickDoesNotLiftLevel() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.clicks(at: [0.95], over: 1, floor: 0.001, sampleRate: 44_100), sampleRate: 44_100)

        let level = try #require(firstPress.state.input.level)
        #expect(abs(level - (-60.0)) < 0.01)
    }

    @Test("Digital silence shows the bottom of the meter rather than minus infinity")
    func digitalSilence() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Array(repeating: 0, count: 4_410), sampleRate: 44_100)

        #expect(firstPress.state.input.level == InputState.minimumLevel)
    }

    @Test("Audio from any input other than the chosen one is ignored")
    func otherInputIgnored() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.5, seconds: 1, sampleRate: 44_100), sampleRate: 44_100, from: AudioInputDevice.mic.id)

        #expect(firstPress.state.input.level == nil)
    }

    @Test("Unplugging the deck clears the level")
    func unplugClearsLevel() throws {
        let (input, firstPress) = capturingDeck()
        input.feed(Signal.square(amplitude: 0.5, seconds: 1, sampleRate: 44_100), sampleRate: 44_100)

        input.unplug(AudioInputDevice.deck.id)

        #expect(firstPress.state.input.level == nil)
    }

    @Test("A sample rate other than 44.1 or 48 kHz is refused and shown")
    func unsupportedRate() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.5, seconds: 1, sampleRate: 96_000), sampleRate: 96_000)

        #expect(firstPress.state.input.status == .unsupportedSampleRate(96_000))
        #expect(firstPress.state.input.level == nil)
    }
}
