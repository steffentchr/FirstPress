import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Screen blanker")
struct ScreenBlankerTests {
    private let rate = 44_100.0
    /// −20 dBFS: music, well above the −50 dBFS default threshold.
    private let music: Float = 0.1
    /// −60 dBFS: a quiet floor, below the threshold.
    private let floor: Float = 0.001

    private func firstPress(blankAfter: BlankAfter, store: FakeStore? = nil) -> (FakeAudioInput, FakeScheduler, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let store = store ?? FakeStore(settings: Settings(inputID: "usb-deck", blankAfter: blankAfter))
        let firstPress = FirstPress(audioInput: input, store: store, scheduler: scheduler)
        firstPress.start()
        return (input, scheduler, firstPress)
    }

    @Test("The screen blanks after the blank-after time")
    func blanks() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60))

        scheduler.advance(by: 59)
        #expect(firstPress.state.screen.isBlanked == false)

        scheduler.advance(by: 1)
        #expect(firstPress.state.screen.isBlanked == true)
    }

    @Test("Never never blanks")
    func never() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .never)

        scheduler.advance(by: 24 * 60 * 60)

        #expect(firstPress.state.screen.isBlanked == false)
    }

    @Test("The first touch on a blank screen only wakes it")
    func firstTouchWakes() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        scheduler.advance(by: 60)

        let consumed = firstPress.screenTouched()

        #expect(consumed == true)
        #expect(firstPress.state.screen.isBlanked == false)
        #expect(firstPress.screenTouched() == false)
    }

    @Test("A touch restarts the blank-after time")
    func touchRestartsTimer() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        scheduler.advance(by: 50)

        firstPress.screenTouched()
        scheduler.advance(by: 50)
        #expect(firstPress.state.screen.isBlanked == false)

        scheduler.advance(by: 10)
        #expect(firstPress.state.screen.isBlanked == true)
    }

    @Test("Coming to the foreground wakes a blank screen and restarts the blank-after time, like a touch")
    func foregroundWakes() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        scheduler.advance(by: 60)
        #expect(firstPress.state.screen.isBlanked == true)

        firstPress.cameToForeground()
        #expect(firstPress.state.screen.isBlanked == false)

        scheduler.advance(by: 59)
        #expect(firstPress.state.screen.isBlanked == false)
        // The first touch after waking is a normal touch: nothing swallows it.
        #expect(firstPress.screenTouched() == false)
        scheduler.advance(by: 60)
        #expect(firstPress.state.screen.isBlanked == true)
    }

    @Test("Coming to the foreground before the screen blanked restarts the blank-after time")
    func foregroundRestartsTimer() {
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        scheduler.advance(by: 50)

        firstPress.cameToForeground()
        scheduler.advance(by: 50)
        #expect(firstPress.state.screen.isBlanked == false)

        scheduler.advance(by: 10)
        #expect(firstPress.state.screen.isBlanked == true)
    }

    @Test("A Record starting wakes the screen")
    func recordStartWakes() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        scheduler.advance(by: 60)
        #expect(firstPress.state.screen.isBlanked == true)

        input.play(Signal.square(amplitude: music, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 1, record: .playing))
        #expect(firstPress.state.screen.isBlanked == false)
    }

    @Test("The screen never blanks while a Record is playing, Gaps included")
    func noBlankingWhilePlaying() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .after(60))

        for _ in 0..<4 {
            input.play(Signal.square(amplitude: music, seconds: 50, sampleRate: rate), sampleRate: rate, on: scheduler)
            input.play(Signal.square(amplitude: floor, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
            #expect(firstPress.state.session == .running(records: 1, record: .gap))
        }
        input.play(Signal.square(amplitude: music, seconds: 50, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.session == .running(records: 1, record: .playing))
        #expect(firstPress.state.screen.isBlanked == false)
    }

    @Test("Once the Record ends with a Flip, the screen blanks after the blank-after time of silence, and a touch restarts it")
    func blanksAfterFlip() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        // The Flip comes about 12.5 s into the silence; the screen blanks 60 s after it.
        input.play(Signal.square(amplitude: floor, seconds: 71, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
        #expect(firstPress.state.screen.isBlanked == false)

        input.play(Signal.square(amplitude: floor, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.screen.isBlanked == true)

        #expect(firstPress.screenTouched() == true)
        scheduler.advance(by: 59)
        #expect(firstPress.state.screen.isBlanked == false)
        scheduler.advance(by: 1)
        #expect(firstPress.state.screen.isBlanked == true)
    }

    @Test("A touch while a Record is playing does not start the blank-after time")
    func touchWhilePlaying() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.screenTouched() == false)
        input.play(Signal.square(amplitude: music, seconds: 120, sampleRate: rate), sampleRate: rate, on: scheduler)

        #expect(firstPress.state.screen.isBlanked == false)
    }

    @Test("Changing the blank-after time applies from now, and is remembered across a restart")
    func setBlankAfter() {
        let store = FakeStore(settings: Settings(inputID: "usb-deck", blankAfter: .after(60)))
        let (_, scheduler, firstPress) = firstPress(blankAfter: .after(60), store: store)
        scheduler.advance(by: 30)

        firstPress.setBlankAfter(.never)
        scheduler.advance(by: 600)
        #expect(firstPress.state.screen.isBlanked == false)
        #expect(firstPress.state.screen.blankAfter == .never)

        let (_, relaunchedScheduler, relaunched) = self.firstPress(blankAfter: .after(60), store: store)
        relaunchedScheduler.advance(by: 600)
        #expect(relaunched.state.screen.blankAfter == .never)
        #expect(relaunched.state.screen.isBlanked == false)
    }

    @Test("Kiosk mode is off on a fresh install, and switching it on is remembered across a restart")
    func kioskMode() {
        let store = FakeStore(settings: Settings(inputID: "usb-deck"))
        let (_, _, firstPress) = firstPress(blankAfter: .after(60), store: store)
        #expect(firstPress.state.screen.isKiosk == false)

        firstPress.setKiosk(true)
        #expect(firstPress.state.screen.isKiosk == true)

        let (_, _, relaunched) = self.firstPress(blankAfter: .after(60), store: store)
        #expect(relaunched.state.screen.isKiosk == true)
    }

    @Test("The appearance is Dark on a fresh install, and the choice is remembered across a restart")
    func appearance() {
        let store = FakeStore(settings: Settings(inputID: "usb-deck"))
        let (_, _, firstPress) = firstPress(blankAfter: .after(60), store: store)
        #expect(firstPress.state.screen.appearance == .dark)

        firstPress.setAppearance(.light)
        #expect(firstPress.state.screen.appearance == .light)

        let (_, _, relaunched) = self.firstPress(blankAfter: .after(60), store: store)
        #expect(relaunched.state.screen.appearance == .light)

        relaunched.setAppearance(.system)
        #expect(relaunched.state.screen.appearance == .system)
    }

    @Test("Settings saved before the appearance could be chosen load as Dark, the look they had")
    func oldSettingsLoadDark() throws {
        let saved = Data(#"{"inputID":"usb-deck","rooms":{},"kiosk":true}"#.utf8)

        let settings = try JSONDecoder().decode(Settings.self, from: saved)

        #expect(settings.appearance == .dark)
        #expect(settings.kiosk == true)
    }

    @Test("In kiosk mode, Now Playing's icons hide after 30 s without a touch and come back on a touch")
    func kioskHidesControls() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .after(60))
        firstPress.setKiosk(true)
        #expect(firstPress.state.hidesControls == false)

        input.play(Signal.square(amplitude: music, seconds: 5, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.page == .nowPlaying)
        input.play(Signal.square(amplitude: music, seconds: 30, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.hidesControls == true)

        firstPress.screenTouched()
        #expect(firstPress.state.hidesControls == false)
        input.play(Signal.square(amplitude: music, seconds: 29, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.hidesControls == false)
        input.play(Signal.square(amplitude: music, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.hidesControls == true)

        firstPress.setKiosk(false)
        #expect(firstPress.state.hidesControls == false)
    }

    @Test("Outside kiosk mode, and on the waiting screen, the icons always show")
    func controlsShowOtherwise() {
        let (input, scheduler, firstPress) = firstPress(blankAfter: .never)
        input.play(Signal.square(amplitude: music, seconds: 60, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.page == .nowPlaying)
        #expect(firstPress.state.hidesControls == false)

        firstPress.setKiosk(true)
        input.play(Signal.square(amplitude: floor, seconds: 120, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.page == .waiting)
        #expect(firstPress.state.hidesControls == false)
    }

    @Test("By default the screen blanks after five minutes")
    func defaultBlankAfter() {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let firstPress = FirstPress(audioInput: input, store: FakeStore(), scheduler: scheduler)
        firstPress.start()

        #expect(firstPress.state.screen.blankAfter == .after(300))
        scheduler.advance(by: 300)
        #expect(firstPress.state.screen.isBlanked == true)
    }
}
