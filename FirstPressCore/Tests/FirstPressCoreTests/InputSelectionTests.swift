import Testing
import FirstPressCore

@MainActor
@Suite("Choosing the input")
struct InputSelectionTests {
    @Test("With no input chosen, nothing is captured, not even the built-in mic")
    func noInputChosen() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(), scheduler: FakeScheduler())

        firstPress.start()

        #expect(firstPress.state.input.status == .notChosen)
        #expect(firstPress.state.input.available == [.mic, .deck])
        #expect(input.startedInputs.isEmpty)
    }

    @Test("Choosing the deck in Settings captures from the deck and is remembered across a restart")
    func chooseDeck() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let store = FakeStore()
        let firstPress = FirstPress(audioInput: input, store: store, scheduler: FakeScheduler())
        firstPress.start()

        firstPress.chooseInput(AudioInputDevice.deck.id)

        #expect(input.startedInputs == ["usb-deck"])
        #expect(firstPress.state.input.status == .present)
        #expect(firstPress.state.input.chosenID == "usb-deck")

        let relaunchedInput = FakeAudioInput(availableInputs: [.mic, .deck])
        let relaunched = FirstPress(audioInput: relaunchedInput, store: store, scheduler: FakeScheduler())
        relaunched.start()

        #expect(relaunchedInput.startedInputs == ["usb-deck"])
        #expect(relaunched.state.input.status == .present)
    }

    @Test("When the chosen deck isn't plugged in, the input is missing and the mic is not used instead")
    func deckMissingAtLaunch() {
        let input = FakeAudioInput(availableInputs: [.mic])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(settings: Settings(inputID: "usb-deck")), scheduler: FakeScheduler())

        firstPress.start()

        #expect(firstPress.state.input.status == .missing)
        #expect(input.startedInputs.isEmpty)
    }

    @Test("The built-in mic is used when the listener chooses it")
    func micChosenOnPurpose() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let firstPress = FirstPress(audioInput: input, store: FakeStore(), scheduler: FakeScheduler())
        firstPress.start()

        firstPress.chooseInput(AudioInputDevice.mic.id)

        #expect(input.startedInputs == ["built-in-mic"])
        #expect(firstPress.state.input.status == .present)
    }

    @Test("The chosen input's name is known while it's unplugged, and after a restart with it still unplugged")
    func chosenNameWhileMissing() {
        let input = FakeAudioInput(availableInputs: [.mic, .deck])
        let store = FakeStore()
        let firstPress = FirstPress(audioInput: input, store: store, scheduler: FakeScheduler())
        firstPress.start()
        #expect(firstPress.state.input.chosenName == nil)

        firstPress.chooseInput(AudioInputDevice.deck.id)
        #expect(firstPress.state.input.chosenName == "Numark TT USB")

        input.unplug(AudioInputDevice.deck.id)
        #expect(firstPress.state.input.status == .missing)
        #expect(firstPress.state.input.chosenName == "Numark TT USB")

        let relaunched = FirstPress(audioInput: FakeAudioInput(availableInputs: [.mic]), store: store, scheduler: FakeScheduler())
        relaunched.start()
        #expect(relaunched.state.input.status == .missing)
        #expect(relaunched.state.input.chosenName == "Numark TT USB")
    }
}
