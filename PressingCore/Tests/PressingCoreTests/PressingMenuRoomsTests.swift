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

    @Test("Pressing Menu shows the phone's markers: a Room that can't be reached, and one taken over in the Sonos app")
    func markers() async {
        let (world, menu, _) = await session()
        #expect(menu.rooms.allSatisfy { $0.marker == nil })

        world.sonos.play("x-sonos-spotify:track", on: .kitchen)
        world.sonos.lose(.livingRoom)
        world.music(seconds: 6)
        await settle()

        #expect(menu.room(FakeRoom.kitchen.uuid)?.marker == .takenOverInSonosApp)
        #expect(menu.room(FakeRoom.livingRoom.uuid)?.marker == .cantBeReached)
        #expect(menu.room(FakeRoom.bathroom.uuid)?.marker == nil)
    }

    @Test("Switching This iPhone on and off from Pressing Menu switches the Phone output")
    func switchPhoneOutput() async {
        let (world, menu, _) = await session()
        #expect(menu.phoneOutput?.isOn == false)

        menu.switchPhoneOutput(on: true)
        #expect(world.pressing.state.phoneOutput.isOn)
        #expect(world.phoneOutput.isPlaying)
        #expect(menu.phoneOutput?.isOn == true)

        menu.switchPhoneOutput(on: false)
        #expect(!world.pressing.state.phoneOutput.isOn)
        #expect(!world.phoneOutput.isPlaying)
        #expect(menu.phoneOutput?.isOn == false)
    }

    @Test("Pressing Menu shows where This iPhone plays, as the Phone output reports its route")
    func phoneOutputRoute() async {
        let (world, menu, _) = await session()
        #expect(menu.phoneOutput?.route == nil)

        world.phoneOutput.report(PhoneOutputRoute(name: "Speaker", kind: .builtInSpeaker))
        #expect(world.pressing.state.phoneOutput.route == PhoneOutputRoute(name: "Speaker", kind: .builtInSpeaker))
        #expect(menu.phoneOutput?.route?.kind == .builtInSpeaker)
        #expect(menu.phoneOutput?.whereItPlays == "iPhone speaker")

        world.phoneOutput.report(PhoneOutputRoute(name: "Kitchen", kind: .airPlay))
        #expect(menu.phoneOutput?.route == PhoneOutputRoute(name: "Kitchen", kind: .airPlay))
        #expect(menu.phoneOutput?.whereItPlays == "AirPlay: Kitchen")

        world.phoneOutput.report(PhoneOutputRoute(name: "AirPods", kind: .bluetooth))
        #expect(menu.phoneOutput?.whereItPlays == "AirPods")

        world.phoneOutput.report(PhoneOutputRoute(name: "Headphones", kind: .wired))
        #expect(menu.phoneOutput?.whereItPlays == "Headphones")

        world.phoneOutput.report(nil)
        #expect(menu.phoneOutput?.route == nil)
        #expect(menu.phoneOutput?.whereItPlays == nil)
    }

    @Test("A route reported before Pressing Menu connects is in its first snapshot")
    func routeOnConnect() {
        let world = World()
        world.phoneOutput.report(PhoneOutputRoute(name: "Kitchen", kind: .airPlay))

        let (menu, _) = world.pressingMenu()

        #expect(menu.phoneOutput?.whereItPlays == "AirPlay: Kitchen")
    }

    @Test("The Rooms summary names the first switched-on Room and counts the rest, This iPhone included, outside a Session too")
    func roomsSummary() async {
        let world = World(sonos: FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]]))
        world.sonos.discover(.kitchen)
        await settle()
        let (menu, _) = world.pressingMenu()
        #expect(menu.roomsSummary == "No Rooms")

        menu.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        #expect(menu.roomsSummary == "Living Room")

        menu.switchRoom(FakeRoom.bathroom.uuid, on: true)
        #expect(menu.roomsSummary == "Bathroom +1")

        menu.switchPhoneOutput(on: true)
        #expect(menu.roomsSummary == "Bathroom +2")

        menu.switchRoom(FakeRoom.bathroom.uuid, on: false)
        menu.switchRoom(FakeRoom.livingRoom.uuid, on: false)
        #expect(menu.roomsSummary == "This iPhone")
    }

    @Test("With no phone connected, the footer shows no Rooms summary")
    func noRoomsSummaryWithoutPhone() {
        let world = World(settings: Settings())
        let (menu, _) = world.pressingMenu()
        #expect(menu.roomsSummary == nil)

        world.pressing.chooseInput(AudioInputDevice.deck.id)
        #expect(menu.roomsSummary == "No Rooms")
    }

    @Test("While the iPhone can't be reached, the Rooms stay on screen and the controls are disabled")
    func controlsDisabledWhileUnreachable() async {
        let (world, menu, link) = await session()
        #expect(menu.canControl)

        link.drop()

        #expect(!menu.canControl)
        #expect(menu.room(FakeRoom.kitchen.uuid)?.isOn == true)
        #expect(menu.roomsSummary == nil)

        world.scheduler.advance(by: 1)
        #expect(menu.canControl)
    }

    @Test("A Pressing Menu that needs an update sends the phone nothing")
    func needsUpdateSendsNothing() async {
        let (world, menu, link) = await session()

        link.deliver(json: #"{"type": "snapshot", "major": 2}"#)
        menu.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        menu.switchPhoneOutput(on: true)
        await settle()

        #expect(!menu.canControl)
        #expect(world.menuServer.received.isEmpty)
        #expect(world.room(.livingRoom)?.isOn == false)
        #expect(!world.pressing.state.phoneOutput.isOn)
    }

    @Test("Dragging a volume slider sends at most 10 volumes a second, the latest each time, plus the final one on release")
    func volumeDrag() async {
        let (world, menu, _) = await session()

        // A drag from 31 to 60 over 0.58 s, a step every 20 ms.
        for volume in 31...60 {
            menu.dragVolume(volume, for: FakeRoom.kitchen.uuid)
            #expect(menu.room(FakeRoom.kitchen.uuid)?.volume == volume)
            world.scheduler.advance(by: 0.02)
        }
        let duringDrag = world.menuServer.received.count
        menu.setVolume(60, for: FakeRoom.kitchen.uuid)
        world.scheduler.advance(by: 1)
        await settle()

        let sent = world.menuServer.received.compactMap(MenuWire.decodeCommand)
        // 0.6 s of dragging: at most 7, one every 0.1 s.
        #expect(duringDrag >= 5 && duringDrag <= 7)
        #expect(sent.first == .setVolume(id: FakeRoom.kitchen.uuid, volume: 31))
        #expect(sent.last == .setVolume(id: FakeRoom.kitchen.uuid, volume: 60))
        #expect(sent.count == duringDrag + 1)
        #expect(world.room(.kitchen)?.volume == 60)
        #expect(world.sonos.volume(of: .kitchen) == 60)
        #expect(menu.room(FakeRoom.kitchen.uuid)?.volume == 60)
    }

    @Test("An older phone without the route still works, and a route kind added later reads as other")
    func olderAndNewerPhones() {
        let world = World()
        let (menu, link) = world.pressingMenu()

        link.deliver(json: """
            {"type": "snapshot", "major": 1, "page": "waiting",
             "rooms": [{"id": "RINCON_A", "name": "Study", "isOn": true, "volume": 25, "isReachable": true, "isSteppedBack": false}],
             "phoneOutput": {"isOn": true}}
            """)
        #expect(menu.rooms.map(\.name) == ["Study"])
        #expect(menu.phoneOutput?.isOn == true)
        #expect(menu.phoneOutput?.whereItPlays == nil)
        #expect(menu.roomsSummary == "Study +1")

        link.deliver(json: """
            {"type": "snapshot", "major": 1, "page": "waiting",
             "phoneOutput": {"isOn": false, "route": {"name": "Vision Pro", "kind": "spatial"}}}
            """)
        #expect(menu.phoneOutput?.route == PhoneOutputRoute(name: "Vision Pro", kind: .other))
        #expect(menu.phoneOutput?.whereItPlays == "Vision Pro")
        #expect(menu.roomsSummary == "No Rooms")
    }

    @Test("A command for a Room the phone doesn't know is ignored")
    func unknownRoomIgnored() async {
        let (world, menu, link) = await session()
        let settings = world.store.settings
        let sent = world.menuServer.sentCount
        let mark = world.sonos.mark

        // From a Pressing Menu whose list is stale.
        link.send(Data(#"{"type": "switchRoom", "major": 1, "id": "RINCON_GONE01400", "on": true}"#.utf8))
        link.send(Data(#"{"type": "setVolume", "major": 1, "id": "RINCON_GONE01400", "volume": 80}"#.utf8))
        await settle()

        #expect(world.store.settings == settings)
        #expect(world.menuServer.sentCount == sent)
        #expect(world.sonos.requests(to: .kitchen, since: mark).allSatisfy { $0.action.hasPrefix("Get") })
        #expect(menu.rooms.map(\.id).contains("RINCON_GONE01400") == false)
    }

    @Test("A command from Pressing Menu doesn't wake a blank phone screen or restart its blank-after time")
    func screenStaysBlank() async {
        let world = World(settings: Settings(inputID: AudioInputDevice.deck.id, blankAfter: .after(60)))
        world.sonos.discover(.kitchen)
        await settle()
        let (menu, _) = world.pressingMenu()

        world.scheduler.advance(by: 50)
        menu.switchRoom(FakeRoom.kitchen.uuid, on: true)
        world.scheduler.advance(by: 10)
        #expect(world.pressing.state.screen.isBlanked)

        menu.setVolume(30, for: FakeRoom.kitchen.uuid)
        menu.switchRoom(FakeRoom.kitchen.uuid, on: false)
        #expect(world.pressing.state.screen.isBlanked)
        #expect(world.room(.kitchen)?.volume == 30)
    }

    @Test("A command from Pressing Menu doesn't bring back kiosk mode's icons")
    func kioskIconsStayHidden() async {
        let world = World(settings: Settings(inputID: AudioInputDevice.deck.id, kiosk: true))
        world.sonos.discover(.kitchen)
        await settle()
        let (menu, _) = world.pressingMenu()
        world.music(seconds: 35)
        #expect(world.pressing.state.hidesControls)

        menu.switchRoom(FakeRoom.kitchen.uuid, on: true)
        await settle()

        #expect(world.room(.kitchen)?.isOn == true)
        #expect(world.pressing.state.hidesControls)
    }
}
