import Testing
import PressingCore

@MainActor
@Suite("Screen blanker")
struct ScreenBlankerTests {
    private let rate = 44_100.0

    private func pressing(blankAfter: BlankAfter, store: FakeStore? = nil) -> (FakeAudioInput, FakeScheduler, Pressing) {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let store = store ?? FakeStore(settings: Settings(inputID: "usb-deck", blankAfter: blankAfter))
        let pressing = Pressing(audioInput: input, store: store, scheduler: scheduler)
        pressing.start()
        return (input, scheduler, pressing)
    }

    @Test("The screen blanks after the blank-after time")
    func blanks() {
        let (_, scheduler, pressing) = pressing(blankAfter: .after(60))

        scheduler.advance(by: 59)
        #expect(pressing.state.screen.isBlanked == false)

        scheduler.advance(by: 1)
        #expect(pressing.state.screen.isBlanked == true)
    }

    @Test("Never never blanks")
    func never() {
        let (_, scheduler, pressing) = pressing(blankAfter: .never)

        scheduler.advance(by: 24 * 60 * 60)

        #expect(pressing.state.screen.isBlanked == false)
    }

    @Test("The first touch on a blank screen only wakes it")
    func firstTouchWakes() {
        let (_, scheduler, pressing) = pressing(blankAfter: .after(60))
        scheduler.advance(by: 60)

        let consumed = pressing.screenTouched()

        #expect(consumed == true)
        #expect(pressing.state.screen.isBlanked == false)
        #expect(pressing.screenTouched() == false)
    }

    @Test("A touch restarts the blank-after time")
    func touchRestartsTimer() {
        let (_, scheduler, pressing) = pressing(blankAfter: .after(60))
        scheduler.advance(by: 50)

        pressing.screenTouched()
        scheduler.advance(by: 50)
        #expect(pressing.state.screen.isBlanked == false)

        scheduler.advance(by: 10)
        #expect(pressing.state.screen.isBlanked == true)
    }

    @Test("A Record starting wakes the screen and restarts the blank-after time")
    func recordStartWakes() {
        let (input, scheduler, pressing) = pressing(blankAfter: .after(60))
        scheduler.advance(by: 60)

        input.play(Signal.square(amplitude: 0.1, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(pressing.state.session == .running(records: 1, record: .playing))
        #expect(pressing.state.screen.isBlanked == false)

        input.play(Signal.square(amplitude: 0.1, seconds: 58, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(pressing.state.screen.isBlanked == false)
        input.play(Signal.square(amplitude: 0.1, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(pressing.state.screen.isBlanked == true)
    }

    @Test("Changing the blank-after time applies from now, and is remembered across a restart")
    func setBlankAfter() {
        let store = FakeStore(settings: Settings(inputID: "usb-deck", blankAfter: .after(60)))
        let (_, scheduler, pressing) = pressing(blankAfter: .after(60), store: store)
        scheduler.advance(by: 30)

        pressing.setBlankAfter(.never)
        scheduler.advance(by: 600)
        #expect(pressing.state.screen.isBlanked == false)
        #expect(pressing.state.screen.blankAfter == .never)

        let (_, relaunchedScheduler, relaunched) = self.pressing(blankAfter: .after(60), store: store)
        relaunchedScheduler.advance(by: 600)
        #expect(relaunched.state.screen.blankAfter == .never)
        #expect(relaunched.state.screen.isBlanked == false)
    }

    @Test("By default the screen blanks after five minutes")
    func defaultBlankAfter() {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let pressing = Pressing(audioInput: input, store: FakeStore(), scheduler: scheduler)
        pressing.start()

        #expect(pressing.state.screen.blankAfter == .after(300))
        scheduler.advance(by: 300)
        #expect(pressing.state.screen.isBlanked == true)
    }
}
