import Testing
import PressingCore

@MainActor
@Suite("Choosing the input")
struct InputSelectionTests {
    @Test("With no input chosen, nothing is captured, not even the built-in mic")
    func noInputChosen() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let pressing = Pressing(audioInput: input, store: FakeStore())

        pressing.start()

        #expect(pressing.state.input.status == .notChosen)
        #expect(pressing.state.input.available == [.mic, .deck])
        #expect(input.startedInputs.isEmpty)
    }

    @Test("Choosing the deck in Settings captures from the deck and is remembered across a restart")
    func chooseDeck() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let store = FakeStore()
        let pressing = Pressing(audioInput: input, store: store)
        pressing.start()

        pressing.chooseInput(AudioInputDevice.deck.id)

        #expect(input.startedInputs == ["usb-deck"])
        #expect(pressing.state.input.status == .present)
        #expect(pressing.state.input.chosenID == "usb-deck")

        let relaunchedInput = FakeAudioInput(availableInputs: [.mic, .deck])
        let relaunched = Pressing(audioInput: relaunchedInput, store: store)
        relaunched.start()

        #expect(relaunchedInput.startedInputs == ["usb-deck"])
        #expect(relaunched.state.input.status == .present)
    }

    @Test("When the chosen deck isn't plugged in, the input is missing and the mic is not used instead")
    func deckMissingAtLaunch() {
        let input = FakeAudioInput(availableInputs: [.mic])
        let pressing = Pressing(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")))

        pressing.start()

        #expect(pressing.state.input.status == .missing)
        #expect(input.startedInputs.isEmpty)
    }

    @Test("The built-in mic is used when the listener chooses it")
    func micChosenOnPurpose() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let pressing = Pressing(audioInput: input, store: FakeStore())
        pressing.start()

        pressing.chooseInput(AudioInputDevice.mic.id)

        #expect(input.startedInputs == ["built-in-mic"])
        #expect(pressing.state.input.status == .present)
    }
}
