import Foundation
import Testing
import PressingCore

@MainActor
@Suite("Rooms coming and going")
struct ReachabilityTests {
    @Test("A player Bonjour loses marks its Room unreachable; found again, it is reachable")
    func lostAndFound() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [])

        sonos.lose(.livingRoom)
        #expect(world.room(.livingRoom)?.isReachable == false)
        #expect(world.room(.kitchen)?.isReachable == true)

        sonos.discover(.livingRoom)
        await settle()
        #expect(world.room(.livingRoom)?.isReachable == true)
    }

    @Test("A switched-on Room found only after the Session started is taken over")
    func foundDuringSession() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen]])
        var settings = Settings(inputID: AudioInputDevice.deck.id)
        settings.rooms[FakeRoom.kitchen.uuid] = RoomChoice(isOn: true, volume: 30)
        let world = World(settings: settings, sonos: sonos)
        world.music(seconds: 3)
        await settle()

        sonos.discover(.livingRoom)
        await settle()

        #expect(sonos.calls(to: .kitchen) == Calls.lead(volume: 30))
    }

    @Test("A held Room that drops off the network is let go, not stepped back; when it returns it rejoins")
    func heldRoomReturns() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30), (.bathroom, 20)])
        world.music(seconds: 3)
        await settle()

        // Kitchen reboots: it vanishes, then comes back on its own.
        sonos.lose(.kitchen)
        sonos.ungroup(.kitchen)
        world.music(seconds: 6)
        await settle()
        let mark = sonos.mark
        sonos.discover(.kitchen)
        await settle()

        #expect(world.room(.kitchen)?.isSteppedBack == false)
        #expect(world.room(.kitchen)?.isReachable == true)
        #expect(sonos.calls(to: .kitchen, since: mark) == Calls.join(.bathroom, volume: 30))
    }

    @Test("A leader that drops off the network: the others re-form under a new leader")
    func leaderLost() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30), (.bathroom, 20), (.livingRoom, 40)])
        world.music(seconds: 3)
        await settle()
        let mark = sonos.mark

        sonos.unreachable = [FakeRoom.bathroom.host]
        sonos.lose(.bathroom)
        await settle()

        #expect(world.room(.bathroom)?.isReachable == false)
        #expect(sonos.calls(to: .kitchen, since: mark) == [Calls.leave] + Calls.lead(volume: 30))
        // Both were grouped under the lost leader, so both leave that group first.
        #expect(sonos.calls(to: .livingRoom, since: mark) == [Calls.leave] + Calls.join(.kitchen, volume: 40))
    }
}
