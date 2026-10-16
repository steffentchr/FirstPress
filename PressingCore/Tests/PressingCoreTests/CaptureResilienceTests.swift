import Testing
import PressingCore

@MainActor
@Suite("Capture restarts on its own")
struct CaptureResilienceTests {
    private func capturingDeck() -> (FakeAudioInput, Pressing) {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let pressing = Pressing(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())
        pressing.start()
        return (input, pressing)
    }

    @Test("Unplugging the deck shows it missing and does not switch to the mic")
    func unplugDeck() {
        let (input, pressing) = capturingDeck()

        input.unplug(AudioInputDevice.deck.id)

        #expect(pressing.state.input.status == .missing)
        #expect(pressing.state.input.available == [.mic])
        #expect(input.startedInputs == ["usb-deck"])
    }

    @Test("Plugging the deck back in restarts capture from it")
    func replugDeck() {
        let (input, pressing) = capturingDeck()
        input.unplug(AudioInputDevice.deck.id)

        input.plugIn(.deck)

        #expect(pressing.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("Any route change with the deck still present restarts capture from the deck")
    func unrelatedRouteChange() {
        let (input, pressing) = capturingDeck()

        input.unplug(AudioInputDevice.mic.id)

        #expect(pressing.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("An interruption pauses capture and its end restarts it")
    func interruption() {
        let (input, pressing) = capturingDeck()

        input.send(.interruptionBegan)
        #expect(pressing.state.input.status == .interrupted)

        input.send(.interruptionEnded)
        #expect(pressing.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("A media-services reset restarts capture")
    func mediaServicesReset() {
        let (input, pressing) = capturingDeck()

        input.send(.mediaServicesReset)

        #expect(pressing.state.input.status == .present)
        #expect(input.startedInputs == ["usb-deck", "usb-deck"])
    }

    @Test("A denied microphone permission is shown as such")
    func permissionDenied() {
        let input = FakeAudioInput(availableInputs: [.deck])
        input.startError = .permissionDenied
        let pressing = Pressing(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())

        pressing.start()

        #expect(pressing.state.input.status == .permissionDenied)
    }

    @Test("If the system routes elsewhere when capture starts, the input is missing")
    func routedElsewhere() {
        let input = FakeAudioInput(availableInputs: [.deck])
        input.startError = .inputUnavailable
        let pressing = Pressing(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())

        pressing.start()

        #expect(pressing.state.input.status == .missing)
    }
}
