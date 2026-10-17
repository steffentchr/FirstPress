import Foundation
import Testing
import PressingCore
import PressingMenuCore

@MainActor
@Suite("Rooms from Pressing Menu")
struct PressingMenuRoomsTests {
    /// A Session running with Kitchen held at volume 30; Living Room and
    /// Bathroom found and switched off. A Pressing Menu is connected.
    private func session() async -> (World, PressingMenu, FakeMenuLink) {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30)])
        let (menu, link) = world.pressingMenu()
        world.music(seconds: 3)
        await settle()
        return (world, menu, link)
    }

    @Test("Switching a Room on from Pressing Menu takes it over at once, mid-Session, and switching it off lets it go")
    func switchRoom() async {
        let (world, menu, _) = await session()

        menu.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        await settle()

        #expect(world.room(.livingRoom)?.isOn == true)
        #expect(world.sonos.source(of: .livingRoom) == Calls.stream)
        #expect(world.sonos.group(of: .livingRoom).contains(.kitchen))
        #expect(menu.rooms.first { $0.id == FakeRoom.livingRoom.uuid }?.isOn == true)

        menu.switchRoom(FakeRoom.livingRoom.uuid, on: false)
        await settle()

        #expect(world.room(.livingRoom)?.isOn == false)
        #expect(world.sonos.group(of: .livingRoom) == [.livingRoom])
        #expect(world.sonos.transportState(of: .livingRoom) == "STOPPED")
        #expect(menu.rooms.first { $0.id == FakeRoom.livingRoom.uuid }?.isOn == false)
    }

    @Test("Setting a volume from Pressing Menu reaches the Room")
    func setVolume() async {
        let (world, menu, _) = await session()

        menu.setVolume(45, for: FakeRoom.kitchen.uuid)
        await settle()

        #expect(world.room(.kitchen)?.volume == 45)
        #expect(world.sonos.volume(of: .kitchen) == 45)
        #expect(menu.room(FakeRoom.kitchen.uuid)?.volume == 45)
    }

    @Test("A volume changed on the phone, or in the Sonos app, moves Pressing Menu's slider")
    func volumeFollowsThePhone() async {
        let (world, menu, _) = await session()

        world.pressing.setVolume(12, for: FakeRoom.kitchen.uuid)
        #expect(menu.room(FakeRoom.kitchen.uuid)?.volume == 12)
        await settle()

        world.sonos.pressVolume(44, on: .kitchen)
        world.music(seconds: 6)
        await settle()
        #expect(menu.room(FakeRoom.kitchen.uuid)?.volume == 44)
    }
}
