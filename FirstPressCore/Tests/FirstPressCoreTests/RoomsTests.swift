import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Rooms")
struct RoomsTests {
    @Test("First Press looks for Sonos players from launch")
    func discoversAtLaunch() {
        let world = World()

        #expect(world.sonos.network.isDiscovering)
    }

    @Test("The first player found is asked for the topology on port 1400, and its Rooms are listed")
    func listsRooms() async {
        let world = World()

        world.sonos.discover(.kitchen)
        await settle()

        // Besides the topology, only launch recovery's one read of what each Room plays.
        #expect(world.sonos.allCalls.first == SOAPCall("GetZoneGroupState"))
        #expect(world.sonos.allCalls.dropFirst().allSatisfy { $0.action == "GetMediaInfo" })
        #expect(world.sonos.network.requests.first?.url.host == FakeRoom.kitchen.host)
        #expect(world.sonos.malformed.isEmpty)
        #expect(world.firstPress.state.rooms.map(\.name) == ["Kitchen", "Living Room"])
        #expect(world.firstPress.state.rooms.allSatisfy { !$0.isOn })
    }

    @Test("Bridges, invisible members and satellites are not Rooms")
    func hiddenDevicesSkipped() async {
        let pairedSecondary = FakeRoom(uuid: "RINCON_PAIR2", name: "Living Room", host: "192.168.1.111", invisible: true)
        let sub = FakeRoom(uuid: "RINCON_SUB", name: "Living Room", host: "192.168.1.112", invisible: true)
        var livingRoom = FakeRoom.livingRoom
        livingRoom.satellites = [sub]
        let sonos = FakeSonos(groups: [[livingRoom, pairedSecondary, .kitchen], [.bridge]])
        let world = World(sonos: sonos)

        sonos.discover(.bridge)
        await settle()

        #expect(world.firstPress.state.rooms.map(\.name) == ["Kitchen", "Living Room"])
    }

    @Test("A Room's switch and volume are remembered across a restart")
    func choicesPersist() async {
        let world = World()
        world.sonos.discover(.livingRoom)
        await settle()
        let kitchen = FakeRoom.kitchen.uuid

        world.firstPress.switchRoom(kitchen, on: true)
        world.firstPress.setVolume(18, for: kitchen)
        #expect(world.firstPress.state.rooms.first { $0.id == kitchen }?.isOn == true)
        #expect(world.firstPress.state.rooms.first { $0.id == kitchen }?.volume == 18)

        let relaunched = World(settings: world.store.settings!)
        relaunched.sonos.discover(.livingRoom)
        await settle()
        let room = relaunched.firstPress.state.rooms.first { $0.id == kitchen }
        #expect(room?.isOn == true)
        #expect(room?.volume == 18)
        #expect(relaunched.firstPress.state.rooms.first { $0.id == FakeRoom.livingRoom.uuid }?.isOn == false)
    }

    @Test("Switching a Room on or setting its volume outside a Session sends nothing to the Room")
    func choicesAloneSendNothing() async {
        let world = World()
        world.sonos.discover(.livingRoom)
        await settle()

        world.firstPress.switchRoom(FakeRoom.kitchen.uuid, on: true)
        world.firstPress.setVolume(40, for: FakeRoom.kitchen.uuid)
        await settle()

        #expect(world.sonos.calls(to: .kitchen).isEmpty)
    }

    @Test("A player that can't be reached doesn't stop discovery: the next one found is asked")
    func unreachablePlayer() async {
        let world = World()
        world.sonos.unreachable = [FakeRoom.kitchen.host]

        world.sonos.discover(.kitchen)
        await settle()
        world.sonos.discover(.livingRoom)
        await settle()

        #expect(world.firstPress.state.rooms.map(\.name) == ["Kitchen", "Living Room"])
    }
}
