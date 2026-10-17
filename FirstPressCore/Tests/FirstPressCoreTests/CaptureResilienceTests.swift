import Testing
import FirstPressCore

@MainActor
@Suite("Capture restarts on its own")
struct CaptureResilienceTests {
    private func capturingDeck() -> (FakeAudioInput, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())
        firstPress.start()
        return (input, firstPress)
    }

    @Test("Unplugging the deck shows it missing and does not switch to the mic")
    func unplugDeck() {
        let (input, firstPress) = capturingDeck()

        input.unplug(AudioInputDevice.deck.id)

        #expect(firstPress.state.input.status == .missing)
        #expect(firstPress.state.input.available == [.mic])
        #expect(input.startedInputs == ["usb-deck"])
    }

    @Test("Plugging the deck back in restarts capture from it")
    func replugDeck() {
        let (input, firstPress) = capturingDeck()
        input.unplug(AudioInputDevice.deck.id)

        input.plugIn(.deck)

        #expect(firstPress.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("Any route change with the deck still present restarts capture from the deck")
    func unrelatedRouteChange() {
        let (input, firstPress) = capturingDeck()

        input.unplug(AudioInputDevice.mic.id)

        #expect(firstPress.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("An interruption pauses capture and its end restarts it")
    func interruption() {
        let (input, firstPress) = capturingDeck()

        input.send(.interruptionBegan)
        #expect(firstPress.state.input.status == .interrupted)

        input.send(.interruptionEnded)
        #expect(firstPress.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("A media-services reset restarts capture")
    func mediaServicesReset() {
        let (input, firstPress) = capturingDeck()

        input.send(.mediaServicesReset)

        #expect(firstPress.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("A denied microphone permission is shown as such")
    func permissionDenied() {
        let input = FakeAudioInput(availableInputs: [.deck])
        input.startError = .permissionDenied
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())

        firstPress.start()

        #expect(firstPress.state.input.status == .permissionDenied)
    }

    @Test("If the system routes elsewhere when capture starts, the input is missing")
    func routedElsewhere() {
        let input = FakeAudioInput(availableInputs: [.deck])
        input.startError = .inputUnavailable
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())

        firstPress.start()

        #expect(firstPress.state.input.status == .missing)
    }
}
