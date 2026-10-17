import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Phone output")
struct PhoneOutputTests {
    @Test("Off on a fresh install: a Session plays nothing through the phone")
    func offByDefault() {
        let world = World()

        world.music(seconds: 10)

        #expect(world.firstPress.state.session != .idle)
        #expect(world.firstPress.state.phoneOutput.isOn == false)
        #expect(world.phoneOutput.played.isEmpty)
        #expect(!world.phoneOutput.isPlaying)
        #expect(!world.phoneOutput.isSwitchedOn)
    }

    @Test("Switched on, the Record plays on the phone from Record start, as captured: not before, not resampled")
    func playsFromRecordStart() {
        let world = World()

        world.firstPress.switchPhoneOutput(on: true)
        world.silence(seconds: 5)
        #expect(world.phoneOutput.isSwitchedOn)
        #expect(!world.phoneOutput.isPlaying)
        #expect(world.phoneOutput.played.isEmpty)

        world.music(seconds: 10, sampleRate: 48_000)

        #expect(world.firstPress.state.phoneOutput.isOn)
        #expect(world.phoneOutput.isPlaying)
        // The Record starts about 2 s in: the level is the median of the last
        // second, then it must stay up for the 1.5 s start delay.
        #expect(abs(world.phoneOutput.playedSeconds - 8) < 0.2)
        #expect(world.phoneOutput.played.allSatisfy { $0.inputID == AudioInputDevice.deck.id && $0.sampleRate == 48_000 })
    }

    @Test("It plays on through Gaps and Flips, and stops when the Session ends: never the run-out groove forever")
    func followsTheSession() {
        let world = World()
        world.firstPress.switchPhoneOutput(on: true)
        world.music(seconds: 10)

        world.silence(seconds: 3)
        world.music(seconds: 10)
        #expect(world.phoneOutput.isPlaying)
        world.silence(seconds: 20)
        #expect(world.firstPress.state.session == .running(records: 1, record: .flipped))
        #expect(world.phoneOutput.isPlaying)
        // Everything since Record start, about 2 s in, the silences included.
        #expect(abs(world.phoneOutput.playedSeconds - 41) < 0.5)

        world.silence(seconds: 30)
        #expect(world.firstPress.state.session == .idle)
        #expect(!world.phoneOutput.isPlaying)
        let playedByTheEnd = world.phoneOutput.played.count
        world.silence(seconds: 10)
        #expect(world.phoneOutput.played.count == playedByTheEnd)
    }

    @Test("Switching on mid-Session starts it at once; switching off stops it at once")
    func switchMidSession() {
        let world = World()
        world.music(seconds: 10)
        #expect(world.phoneOutput.played.isEmpty)

        world.firstPress.switchPhoneOutput(on: true)
        #expect(world.phoneOutput.isPlaying)
        world.music(seconds: 5)
        #expect(abs(world.phoneOutput.playedSeconds - 5) < 0.2)

        world.firstPress.switchPhoneOutput(on: false)
        #expect(!world.phoneOutput.isSwitchedOn)
        #expect(!world.phoneOutput.isPlaying)
        let playedWhenOff = world.phoneOutput.played.count
        world.music(seconds: 5)
        #expect(world.phoneOutput.played.count == playedWhenOff)
        #expect(world.firstPress.state.session == .running(records: 1, record: .playing))
    }

    @Test("The switch is remembered across a restart, and the phone is told at launch")
    func choicePersists() {
        let world = World()
        world.firstPress.switchPhoneOutput(on: true)

        let relaunched = World(settings: world.store.settings!)
        #expect(relaunched.firstPress.state.phoneOutput.isOn)
        #expect(relaunched.phoneOutput.isSwitchedOn)
        #expect(!relaunched.phoneOutput.isPlaying)
        relaunched.music(seconds: 5)
        #expect(relaunched.phoneOutput.isPlaying)

        relaunched.firstPress.switchPhoneOutput(on: false)
        let again = World(settings: relaunched.store.settings!)
        #expect(!again.firstPress.state.phoneOutput.isOn)
    }

    @Test("Switching never touches capture, and only the chosen input is played")
    func captureUntouched() {
        let world = World()
        world.music(seconds: 5)
        let started = world.input.startedInputs
        let stops = world.input.stopCount

        world.firstPress.switchPhoneOutput(on: true)
        world.input.send(.buffer(PCMBuffer(inputID: AudioInputDevice.mic.id, sampleRate: 44_100, time: 0, channels: [[0.1, 0.1]])))
        world.music(seconds: 1)
        world.firstPress.switchPhoneOutput(on: false)

        #expect(world.input.startedInputs == started)
        #expect(world.input.stopCount == stops)
        #expect(world.firstPress.state.input.status == .present)
        #expect(!world.phoneOutput.played.isEmpty)
        #expect(world.phoneOutput.played.allSatisfy { $0.inputID == AudioInputDevice.deck.id })
    }

    @Test("Settings saved before the Phone output existed load with it off")
    func oldSettingsLoadOff() throws {
        let saved = Data(#"{"inputID":"usb-deck","rooms":{}}"#.utf8)

        let settings = try JSONDecoder().decode(Settings.self, from: saved)

        #expect(settings.phoneOutput == false)
        #expect(settings.inputID == AudioInputDevice.deck.id)
    }
}
