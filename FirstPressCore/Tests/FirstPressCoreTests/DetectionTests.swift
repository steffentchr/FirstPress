import Testing
import FirstPressCore

@MainActor
@Suite("Records and Sessions")
struct DetectionTests {
    private let rate = 44_100.0
    /// −20 dBFS: music, well above the −50 dBFS default threshold.
    private let music: Float = 0.1
    /// −60 dBFS: a quiet floor, below the threshold.
    private let floor: Float = 0.001

    private func deck() -> (FakeAudioInput, FakeScheduler, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: scheduler)
        firstPress.start()
        return (input, scheduler, firstPress)
    }

    @Test("Before any music there is no Session")
    func idleAtLaunch() {
        let (_, _, firstPress) = deck()

        #expect(firstPress.state.session == .idle)
    }

    @Test("Music held above the threshold for the start delay starts a Record and a Session")
    func needleDrop() {
        let (input, scheduler, firstPress) = deck()

        input.play(Signal.square(amplitude: music, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 1, record: .playing))
    }

    @Test("Music shorter than the start delay starts nothing")
    func shortBurst() {
        let (input, scheduler, firstPress) = deck()

        input.play(Signal.square(amplitude: music, seconds: 1, sampleRate: rate), sampleRate: rate, on: scheduler)
        input.play(Signal.square(amplitude: floor, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .idle)
    }

    @Test("A 2 s silence is a Gap, and the music after it continues the same Record")
    func gap() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        input.play(Signal.square(amplitude: floor, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .gap))

        input.play(Signal.square(amplitude: music, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .playing))
    }

    @Test("A quiet passage shorter than a Gap is still playing")
    func quietPassage() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        input.play(Signal.square(amplitude: floor, seconds: 1, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 1, record: .playing))
    }

    @Test("A 12 s silence is a Flip and ends the Record, and the Session carries on")
    func flip() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        input.play(Signal.square(amplitude: floor, seconds: 11, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .gap))

        input.play(Signal.square(amplitude: floor, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))
    }

    @Test("A new Record within the stop delay after a Flip stays in the same Session")
    func secondSide() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)
        input.play(Signal.square(amplitude: floor, seconds: 40, sampleRate: rate), sampleRate: rate, on: scheduler)

        input.play(Signal.square(amplitude: music, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 2, record: .playing))
    }

    @Test("With no new Record, the Session ends once the silence reaches the stop delay, counted from when it began")
    func sessionEnds() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        // Flip 12 s into the silence; the Session ends 45 s into it, not 45 s after the Flip.
        input.play(Signal.square(amplitude: floor, seconds: 44, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))

        input.play(Signal.square(amplitude: floor, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
    }

    @Test("Run-out groove clicks over a low floor end the Record at the Flip threshold and the Session at the stop delay", arguments: [1.8, 1.33])
    func runOutGroove(clickEvery: Double) {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        // The stylus sits in the run-out groove and the platter keeps turning:
        // a full-scale click every 1.8 s (33⅓ rpm) or 1.33 s (45 rpm) over a −60 dBFS floor.
        let runOut = Signal.clicks(at: Array(stride(from: 0.5, to: 70, by: clickEvery)), over: 70, floor: floor, sampleRate: rate)
        input.play(Array(runOut[..<Int(14 * rate)]), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))

        input.play(Array(runOut[Int(14 * rate)...]), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
    }

    @Test("A raised hum floor below the threshold does not hold a Record open")
    func hum() throws {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        // −54 dBFS hum, 4 dB under the −50 dBFS threshold.
        input.play(Signal.square(amplitude: 0.002, seconds: 60, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .idle)
        let noiseFloor = try #require(firstPress.state.input.noiseFloor)
        #expect(abs(noiseFloor - (-53.98)) < 0.01)
    }

    @Test("A 48 kHz deck behaves identically")
    func fortyEightKilohertz() {
        let rate = 48_000.0
        let (input, scheduler, firstPress) = deck()

        input.play(Signal.square(amplitude: music, seconds: 1, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)

        input.play(Signal.square(amplitude: music, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .playing))

        input.play(Signal.square(amplitude: floor, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .gap))

        let runOut = Signal.clicks(at: Array(stride(from: 0.5, to: 60, by: 1.8)), over: 60, floor: floor, sampleRate: rate)
        input.play(Array(runOut[..<Int(10 * rate)]), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))

        input.play(Array(runOut[Int(10 * rate)...]), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
    }

    @Test("An input that disappears is silence: the Record flips and the Session ends")
    func unpluggedIsSilence() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        input.unplug(AudioInputDevice.deck.id)
        scheduler.advance(by: 12)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))

        scheduler.advance(by: 32)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))
        scheduler.advance(by: 1)
        #expect(firstPress.state.session == .idle)
    }

    @Test("Reseating the cable within the stop delay carries on with a new Record in the same Session")
    func reseatCable() {
        let (input, scheduler, firstPress) = deck()
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)
        input.unplug(AudioInputDevice.deck.id)
        scheduler.advance(by: 20)

        input.plugIn(.deck)
        input.play(Signal.square(amplitude: music, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 2, record: .playing))
    }

    @Test("A single loud click starts nothing")
    func singleClick() {
        let (input, scheduler, firstPress) = deck()

        input.play(Signal.clicks(at: [1], over: 10, floor: floor, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .idle)
    }
}
