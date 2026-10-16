import Foundation
import Testing
import PressingCore

@MainActor
@Suite("Switching Rooms during a Session")
struct MidSessionTests {
    /// Bathroom leads and Kitchen follows; Living Room is off, at volume 40.
    private func playing() async -> (World, FakeSonos) {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30), (.bathroom, 20)])
        world.pressing.setVolume(40, for: FakeRoom.livingRoom.uuid)
        world.music(seconds: 3)
        await settle()
        return (world, sonos)
    }

    @Test("Switching a Room on takes it over at once: it joins the leader at its volume")
    func switchOnJoins() async {
        let (world, sonos) = await playing()
        let mark = sonos.mark

        world.pressing.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        await settle()

        #expect(sonos.calls(to: .livingRoom, since: mark) == Calls.join(.bathroom, volume: 40))
        #expect(sonos.calls(to: .bathroom, since: mark).isEmpty)
        #expect(sonos.group(of: .bathroom) == [.bathroom, .kitchen, .livingRoom])
    }

    @Test("Switching the only Room on during a Session makes it lead")
    func switchOnLeads() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [])
        world.music(seconds: 3)
        await settle()

        world.pressing.switchRoom(FakeRoom.kitchen.uuid, on: true)
        await settle()

        #expect(sonos.calls(to: .kitchen) == Calls.lead(volume: 25))
    }

    @Test("Switching a following Room off makes it leave the group and stops it; the others play on")
    func switchOffFollower() async {
        let (world, sonos) = await playing()
        let mark = sonos.mark

        world.pressing.switchRoom(FakeRoom.kitchen.uuid, on: false)
        await settle()

        #expect(sonos.calls(to: .kitchen, since: mark) == [Calls.leave, Calls.stop])
        #expect(sonos.calls(to: .bathroom, since: mark).isEmpty)
        #expect(sonos.group(of: .bathroom) == [.bathroom])
        #expect(sonos.transportState(of: .bathroom) == "PLAYING")
    }

    @Test("Switching the leader off stops it and re-forms the group under a new leader")
    func switchOffLeader() async {
        let (world, sonos) = await playing()
        world.pressing.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        await settle()
        let mark = sonos.mark

        world.pressing.switchRoom(FakeRoom.bathroom.uuid, on: false)
        await settle()

        #expect(sonos.calls(to: .bathroom, since: mark) == [Calls.leave, Calls.stop])
        #expect(sonos.calls(to: .kitchen, since: mark) == Calls.lead(volume: 30))
        #expect(sonos.calls(to: .livingRoom, since: mark) == Calls.join(.kitchen, volume: 40))
        #expect(sonos.group(of: .kitchen) == [.kitchen, .livingRoom])
        #expect(sonos.transportState(of: .kitchen) == "PLAYING")
        #expect(sonos.transportState(of: .bathroom) == "STOPPED")
    }

    @Test("A Room switched off mid-Session gets nothing more, not even Stop at the end")
    func switchedOffStaysAlone() async {
        let (world, sonos) = await playing()
        world.pressing.switchRoom(FakeRoom.kitchen.uuid, on: false)
        await settle()
        let mark = sonos.mark

        world.silence(seconds: 60)
        await settle()

        #expect(sonos.requests(to: .kitchen, since: mark).isEmpty)
        #expect(sonos.calls(to: .bathroom, since: mark) == [Calls.stop])
    }

    @Test("Switching Rooms outside a Session sends nothing")
    func outsideSession() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30)])
        let mark = sonos.mark

        world.pressing.switchRoom(FakeRoom.kitchen.uuid, on: false)
        world.pressing.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        await settle()

        #expect(sonos.mark == mark)
    }
}
