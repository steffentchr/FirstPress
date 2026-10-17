import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Watching the Rooms and stepping back")
struct StepBackTests {
    /// Bathroom leads and Kitchen follows; Living Room is off.
    private func playing() async -> (World, FakeSonos) {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30), (.bathroom, 20)])
        world.music(seconds: 3)
        await settle()
        return (world, sonos)
    }

    /// Lets the monitor look at least once.
    private func poll(_ world: World) async {
        world.music(seconds: 6)
        await settle()
    }

    @Test("While all is well, the monitor only reads: no command goes to any Room")
    func quietWhileWell() async {
        let (world, sonos) = await playing()
        let mark = sonos.mark

        await poll(world)

        #expect(sonos.requests(to: .bathroom, since: mark).map(\.action).contains("GetTransportInfo"))
        #expect(sonos.calls(to: .bathroom, since: mark).isEmpty)
        #expect(sonos.calls(to: .kitchen, since: mark).isEmpty)
        #expect(sonos.requests(to: .livingRoom, since: mark).isEmpty)
    }

    @Test("Someone playing something else on the leader: First Press steps back from the whole group without stopping it, for the rest of the Session")
    func foreignSourceOnLeader() async {
        let (world, sonos) = await playing()
        sonos.play("x-sonos-spotify:track", on: .bathroom)

        await poll(world)
        let mark = sonos.mark
        // A Flip and another Record in the same Session.
        world.silence(seconds: 20)
        world.music(seconds: 10)
        // Then the Session ends.
        world.silence(seconds: 60)
        await settle()

        #expect(world.room(.bathroom)?.isSteppedBack == true)
        #expect(world.room(.kitchen)?.isSteppedBack == true)
        #expect(sonos.requests(to: .bathroom, since: mark).isEmpty)
        #expect(sonos.requests(to: .kitchen, since: mark).isEmpty)
        #expect(sonos.transportState(of: .bathroom) == "PLAYING")
        #expect(sonos.source(of: .kitchen) == "x-sonos-spotify:track")
    }

    @Test("The next Session takes stepped-back Rooms over again")
    func nextSessionTakesOverAgain() async {
        let (world, sonos) = await playing()
        sonos.play("x-sonos-spotify:track", on: .bathroom)
        await poll(world)
        world.silence(seconds: 60)
        await settle()
        let mark = sonos.mark

        world.music(seconds: 3)
        await settle()

        #expect(world.room(.bathroom)?.isSteppedBack == false)
        #expect(world.room(.kitchen)?.isSteppedBack == false)
        #expect(sonos.calls(to: .bathroom, since: mark) == Calls.lead(volume: 20))
        #expect(sonos.calls(to: .kitchen, since: mark) == Calls.join(.bathroom, volume: 30))
    }

    @Test("A Room pulled out of the group: First Press steps back from that Room only")
    func memberLeft() async {
        let (world, sonos) = await playing()
        sonos.ungroup(.kitchen)
        sonos.play("x-sonos-spotify:track", on: .kitchen)

        await poll(world)
        let mark = sonos.mark
        sonos.setTransportState("STOPPED", of: .bathroom)
        await poll(world)
        world.silence(seconds: 60)
        await settle()

        #expect(world.room(.kitchen)?.isSteppedBack == true)
        #expect(world.room(.bathroom)?.isSteppedBack == false)
        #expect(sonos.requests(to: .kitchen, since: mark).isEmpty)
        // The leader is still First Press's: resumed, then stopped at the end.
        #expect(sonos.calls(to: .bathroom, since: mark) == [Calls.play, Calls.stop])
    }

    @Test("Switching a stepped-back Room off and on takes it over again in this Session")
    func reclaim() async {
        let (world, sonos) = await playing()
        sonos.ungroup(.kitchen)
        await poll(world)
        let mark = sonos.mark

        world.firstPress.switchRoom(FakeRoom.kitchen.uuid, on: false)
        await settle()
        #expect(sonos.requests(to: .kitchen, since: mark).isEmpty)
        world.firstPress.switchRoom(FakeRoom.kitchen.uuid, on: true)
        await settle()

        #expect(world.room(.kitchen)?.isSteppedBack == false)
        #expect(sonos.calls(to: .kitchen, since: mark) == Calls.join(.bathroom, volume: 30))
    }

    @Test("A leader on the stream that has stopped (a dropout) is told to play again")
    func stoppedResumes() async {
        let (world, sonos) = await playing()
        sonos.setTransportState("STOPPED", of: .bathroom)
        let mark = sonos.mark

        await poll(world)

        #expect(sonos.calls(to: .bathroom, since: mark) == [Calls.play])
        #expect(sonos.transportState(of: .bathroom) == "PLAYING")
        #expect(world.room(.bathroom)?.isSteppedBack == false)
    }

    @Test("A leader on the stream reported paused also resumes, since a pause can't yet be told from a dropout")
    func pausedResumes() async {
        let (world, sonos) = await playing()
        sonos.setTransportState("PAUSED_PLAYBACK", of: .bathroom)
        let mark = sonos.mark

        await poll(world)

        #expect(sonos.calls(to: .bathroom, since: mark) == [Calls.play])
        #expect(world.room(.bathroom)?.isSteppedBack == false)
    }

    @Test("A volume changed in the Sonos app is adopted as the Room's volume, and is not a Step back")
    func volumeAdopted() async {
        let (world, sonos) = await playing()
        sonos.pressVolume(44, on: .kitchen)
        let mark = sonos.mark

        await poll(world)

        #expect(world.room(.kitchen)?.volume == 44)
        #expect(world.room(.kitchen)?.isSteppedBack == false)
        #expect(world.store.settings?.rooms[FakeRoom.kitchen.uuid]?.volume == 44)
        #expect(sonos.calls(to: .kitchen, since: mark).isEmpty)
    }

    @Test("A volume set in First Press is not undone by a read that raced it")
    func ownVolumeNotUndone() async {
        let (world, sonos) = await playing()
        // A poll falls due before the new volume reaches the Room.
        world.music(seconds: 6)
        world.firstPress.setVolume(12, for: FakeRoom.kitchen.uuid)
        await settle()

        #expect(world.room(.kitchen)?.volume == 12)
        #expect(sonos.volume(of: .kitchen) == 12)
    }
}
