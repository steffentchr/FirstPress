import Testing
import FirstPressCore

@MainActor
@Suite("Noise floor")
struct NoiseFloorTests {
    private let rate = 44_100.0

    private func capturingDeck() -> (FakeAudioInput, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.deck])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())
        firstPress.start()
        return (input, firstPress)
    }

    @Test("Music alone gives no noise floor")
    func musicOnly() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.3, seconds: 5, sampleRate: rate), sampleRate: rate)

        #expect(firstPress.state.input.noiseFloor == nil)
    }

    @Test("The run-out groove's clicks don't lift the noise floor", arguments: [1.8, 1.33])
    func runOutGroove(clickEvery: Double) throws {
        let (input, firstPress) = capturingDeck()
        input.feed(Signal.square(amplitude: 0.3, seconds: 5, sampleRate: rate), sampleRate: rate)

        // -60 dBFS floor with a full-scale click every 1.8 s (33⅓ rpm) or 1.33 s (45 rpm).
        let clickTimes = stride(from: 0.5, to: 20, by: clickEvery).map { $0 }
        input.feed(Signal.clicks(at: clickTimes, over: 20, floor: 0.001, sampleRate: rate), sampleRate: rate)

        let floor = try #require(firstPress.state.input.noiseFloor)
        #expect(abs(floor - (-60)) < 0.5)
    }

    @Test("Hum below the threshold shows up as the noise floor")
    func hum() throws {
        let (input, firstPress) = capturingDeck()

        // -54 dBFS hum, below the -50 dBFS start threshold.
        input.feed(Signal.square(amplitude: 0.002, seconds: 5, sampleRate: rate), sampleRate: rate)

        let floor = try #require(firstPress.state.input.noiseFloor)
        #expect(abs(floor - (-53.98)) < 0.01)
    }

    @Test("Choosing another input starts the noise floor afresh")
    func newInputNewFloor() throws {
        let input = FakeAudioInput(availableInputs: [.deck, .mic])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())
        firstPress.start()
        input.feed(Signal.square(amplitude: 0.001, seconds: 5, sampleRate: rate), sampleRate: rate)

        firstPress.chooseInput(AudioInputDevice.mic.id)

        #expect(firstPress.state.input.noiseFloor == nil)
    }

    @Test("The noise floor follows the most recent silence")
    func followsRecentSilence() throws {
        let (input, firstPress) = capturingDeck()

        input.feed(Signal.square(amplitude: 0.001, seconds: 15, sampleRate: rate), sampleRate: rate)
        input.feed(Signal.square(amplitude: 0.002, seconds: 15, sampleRate: rate), sampleRate: rate)

        let floor = try #require(firstPress.state.input.noiseFloor)
        #expect(abs(floor - (-53.98)) < 0.01)
    }
}
