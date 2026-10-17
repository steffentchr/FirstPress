import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Calibrating detection in Settings")
struct DetectionSettingsTests {
    private let rate = 44_100.0

    private func deck(store: FakeStore = FakeStore(settings: Settings(inputID: "usb-deck"))) -> (FakeAudioInput, FakeScheduler, FirstPress) {
        let input = FakeAudioInput(availableInputs: [.deck])
        let scheduler = FakeScheduler()
        let firstPress = FirstPress(audioInput: input, store: store, scheduler: scheduler)
        firstPress.start()
        return (input, scheduler, firstPress)
    }

    @Test("Defaults are −50 dBFS, 1.5 s start delay, 12 s Flip threshold and 45 s stop delay")
    func defaults() {
        let (_, _, firstPress) = deck()

        #expect(firstPress.state.detection == DetectionSettings(threshold: -50, startDelay: 1.5, flipThreshold: 12, stopDelay: 45))
    }

    @Test("A lower threshold lets a quiet deck start a Record, and the noise floor follows it")
    func lowerThreshold() throws {
        let (input, scheduler, firstPress) = deck()
        try firstPress.setDetection(DetectionSettings(threshold: -70, startDelay: 1.5, flipThreshold: 12, stopDelay: 45))

        // −54 dBFS: silence at the default threshold, music at −70.
        input.play(Signal.square(amplitude: 0.002, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .playing))
        #expect(firstPress.state.input.noiseFloor == nil)

        // −80 dBFS is silence at −70.
        input.play(Signal.square(amplitude: 0.0001, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        let noiseFloor = try #require(firstPress.state.input.noiseFloor)
        #expect(abs(noiseFloor - (-80)) < 0.01)
    }

    @Test("The start delay, Flip threshold and stop delay can be lengthened")
    func longerDelays() throws {
        let (input, scheduler, firstPress) = deck()
        try firstPress.setDetection(DetectionSettings(threshold: -50, startDelay: 4, flipThreshold: 20, stopDelay: 60))

        input.play(Signal.square(amplitude: 0.1, seconds: 3, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
        input.play(Signal.square(amplitude: 0.1, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .playing))

        input.play(Signal.square(amplitude: 0.001, seconds: 15, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .gap))
        input.play(Signal.square(amplitude: 0.001, seconds: 10, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))

        // The Session ends about 60.5 s into the silence, counted from when it began.
        input.play(Signal.square(amplitude: 0.001, seconds: 34, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .running(records: 1, record: .flipped))
        input.play(Signal.square(amplitude: 0.001, seconds: 2, sampleRate: rate), sampleRate: rate, on: scheduler)
        #expect(firstPress.state.session == .idle)
    }

    @Test("A stop delay that isn't longer than the Flip threshold is refused", arguments: [12.0, 10.0])
    func stopDelayMustExceedFlip(stopDelay: Double) {
        let (_, _, firstPress) = deck()

        #expect(throws: DetectionSettingsError.stopDelayNotLongerThanFlipThreshold) {
            try firstPress.setDetection(DetectionSettings(threshold: -50, startDelay: 1.5, flipThreshold: 12, stopDelay: stopDelay))
        }
        #expect(firstPress.state.detection.stopDelay == 45)
    }

    @Test("Settings saved before detection was configurable load with the defaults")
    func olderSettingsLoad() throws {
        let saved = Data(#"{"inputID":"usb-deck"}"#.utf8)

        let settings = try JSONDecoder().decode(Settings.self, from: saved)

        #expect(settings == Settings(inputID: "usb-deck", detection: DetectionSettings(threshold: -50, startDelay: 1.5, flipThreshold: 12, stopDelay: 45)))
    }

    @Test("Detection settings are remembered across a restart")
    func remembered() throws {
        let store = FakeStore(settings: Settings(inputID: "usb-deck"))
        let (_, _, firstPress) = deck(store: store)
        let calibrated = DetectionSettings(threshold: -44, startDelay: 2, flipThreshold: 15, stopDelay: 90)

        try firstPress.setDetection(calibrated)

        let (_, _, relaunched) = deck(store: store)
        #expect(relaunched.state.detection == calibrated)
        #expect(relaunched.state.input.chosenID == "usb-deck")
    }
}
