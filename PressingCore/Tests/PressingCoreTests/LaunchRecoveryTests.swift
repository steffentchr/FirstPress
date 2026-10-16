import Foundation
import Testing
import PressingCore

@MainActor
@Suite("Picking Rooms up again after a restart")
struct LaunchRecoveryTests {
    /// Pressing's stream as served before the restart, when the phone had another address.
    private let oldStream = "x-rincon-mp3radio://192.168.1.77:8020/pressing/turntable.mp3"

    /// Kitchen and Living Room switched on, Kitchen still leading the old stream.
    private func relaunch() async -> (World, FakeSonos) {
        let sonos = FakeSonos(groups: [[.kitchen, .livingRoom], [.bathroom]])
        sonos.play(oldStream, on: .kitchen)
        let world = await World.household(sonos, foundThrough: .bathroom, on: [(.kitchen, 30), (.livingRoom, 40)])
        return (world, sonos)
    }

    @Test("Rooms on a Pressing stream from another address are stopped when there is no signal")
    func stoppedWithoutSignal() async {
        let (world, sonos) = await relaunch()

        world.silence(seconds: 10)
        await settle()

        #expect(sonos.calls(to: .kitchen) == [Calls.stop])
        #expect(sonos.calls(to: .livingRoom).isEmpty)
        #expect(sonos.transportState(of: .livingRoom) == "STOPPED")
        #expect(world.pressing.state.session == .idle)
    }

    @Test("Rooms on a Pressing stream are taken into a Session when there is signal")
    func takenIntoSession() async {
        let (world, sonos) = await relaunch()

        world.music(seconds: 15)
        await settle()

        #expect(sonos.calls(to: .kitchen) == Calls.lead(volume: 30))
        #expect(sonos.calls(to: .livingRoom) == Calls.join(.kitchen, volume: 40))
        #expect(sonos.source(of: .livingRoom) == Calls.stream)
        #expect(sonos.transportState(of: .kitchen) == "PLAYING")
    }

    @Test("A Room playing another app's radio stream at launch is left alone")
    func otherRadioLeftAlone() async {
        let sonos = FakeSonos(groups: [[.kitchen], [.bathroom]])
        sonos.play("x-rincon-mp3radio://192.168.1.77:8000/radio.mp3", on: .kitchen)
        let world = await World.household(sonos, foundThrough: .bathroom, on: [(.kitchen, 30)])

        world.silence(seconds: 10)
        await settle()

        #expect(sonos.calls(to: .kitchen).isEmpty)
        #expect(sonos.transportState(of: .kitchen) == "PLAYING")
    }

    @Test("A switched-off Room is not even asked what it plays at launch")
    func switchedOffNotAsked() async {
        let sonos = FakeSonos(groups: [[.kitchen], [.bathroom]])
        sonos.play(oldStream, on: .kitchen)
        let world = await World.household(sonos, foundThrough: .bathroom, on: [])

        world.silence(seconds: 10)
        await settle()

        #expect(sonos.requests(to: .kitchen).isEmpty)
    }
}
