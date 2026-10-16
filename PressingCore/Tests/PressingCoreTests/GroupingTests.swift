import Foundation
import Testing
import PressingCore

/// Shared SOAP calls for the Room tests.
enum Calls {
    static let stream = "x-rincon-mp3radio://192.168.1.50:8020/pressing/turntable.mp3"
    static let didl = #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="R:0/0/0" parentID="R:0/0" restricted="true"><dc:title>Pressing</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item></DIDL-Lite>"#

    static func lead(volume: Int, stream: String = stream) -> [SOAPCall] {
        [
            SOAPCall("SetAVTransportURI", ["InstanceID": "0", "CurrentURI": stream, "CurrentURIMetaData": didl]),
            setVolume(volume),
            SOAPCall("Play", ["InstanceID": "0", "Speed": "1"]),
        ]
    }

    static func join(_ leader: FakeRoom, volume: Int) -> [SOAPCall] {
        [
            SOAPCall("SetAVTransportURI", ["InstanceID": "0", "CurrentURI": "x-rincon:\(leader.uuid)", "CurrentURIMetaData": ""]),
            setVolume(volume),
        ]
    }

    static func setVolume(_ volume: Int) -> SOAPCall {
        SOAPCall("SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "\(volume)"])
    }

    static let leave = SOAPCall("BecomeCoordinatorOfStandaloneGroup", ["InstanceID": "0"])
    static let play = SOAPCall("Play", ["InstanceID": "0", "Speed": "1"])
    static let stop = SOAPCall("Stop", ["InstanceID": "0"])
}

extension World {
    /// The household found through `room`, with these Rooms switched on at these volumes.
    static func household(_ sonos: FakeSonos, foundThrough room: FakeRoom, on rooms: [(FakeRoom, Int)]) async -> World {
        var settings = Settings(inputID: AudioInputDevice.deck.id)
        for (room, volume) in rooms {
            settings.rooms[room.uuid] = RoomChoice(isOn: true, volume: volume)
        }
        let world = World(settings: settings, sonos: sonos)
        sonos.discover(room)
        await settle()
        return world
    }

    func room(_ room: FakeRoom) -> RoomState? {
        pressing.state.rooms.first { $0.id == room.uuid }
    }
}

@MainActor
@Suite("Playing several Rooms in sync")
struct GroupingTests {
    @Test("The first switched-on Room leads and plays; the others join it, each at its own volume")
    func leaderAndFollowers() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.livingRoom, 40), (.kitchen, 30), (.bathroom, 20)])

        world.music(seconds: 3)
        await settle()

        // Rooms are taken in name order: Bathroom leads.
        #expect(sonos.calls(to: .bathroom) == Calls.lead(volume: 20))
        #expect(sonos.calls(to: .kitchen) == Calls.join(.bathroom, volume: 30))
        #expect(sonos.calls(to: .livingRoom) == Calls.join(.bathroom, volume: 40))
        #expect(sonos.group(of: .bathroom) == [.bathroom, .kitchen, .livingRoom])
        #expect(sonos.malformed.isEmpty)
    }

    @Test("A switched-on Room grouped with a switched-off Room is pulled out first; the switched-off Room is never asked anything")
    func pulledOutOfMixedGroup() async {
        let sonos = FakeSonos(groups: [[.livingRoom, .kitchen], [.bathroom]])
        sonos.play("x-sonos-spotify:track", on: .livingRoom)
        let world = await World.household(sonos, foundThrough: .bathroom, on: [(.kitchen, 30), (.bathroom, 20)])

        world.music(seconds: 3)
        world.silence(seconds: 60)
        await settle()

        #expect(sonos.calls(to: .kitchen) == [Calls.leave] + Calls.join(.bathroom, volume: 30))
        #expect(sonos.requests(to: .livingRoom).isEmpty)
        #expect(sonos.source(of: .livingRoom) == "x-sonos-spotify:track")
        #expect(sonos.transportState(of: .livingRoom) == "PLAYING")
    }

    @Test("A leading Room grouped with a switched-off Room leaves that group before it plays")
    func leaderPulledOut() async {
        let sonos = FakeSonos(groups: [[.livingRoom, .bathroom], [.kitchen]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.kitchen, 30), (.bathroom, 20)])

        world.music(seconds: 3)
        await settle()

        #expect(sonos.calls(to: .bathroom) == [Calls.leave] + Calls.lead(volume: 20))
        #expect(sonos.group(of: .bathroom) == [.bathroom, .kitchen])
        #expect(sonos.group(of: .livingRoom) == [.livingRoom])
    }

    @Test("A Room that can't be reached is flagged and skipped; the others play")
    func unreachableRoom() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen], [.bathroom]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.livingRoom, 40), (.kitchen, 30), (.bathroom, 20)])
        sonos.unreachable = [FakeRoom.bathroom.host]

        world.music(seconds: 3)
        await settle()

        #expect(world.room(.bathroom)?.isReachable == false)
        #expect(world.room(.kitchen)?.isReachable == true)
        #expect(sonos.calls(to: .kitchen) == Calls.lead(volume: 30))
        #expect(sonos.calls(to: .livingRoom) == Calls.join(.kitchen, volume: 40))
    }

    @Test("When the Session ends, only the leader gets Stop, and the group stops with it")
    func sessionEndStopsLeader() async {
        let sonos = FakeSonos(groups: [[.livingRoom], [.kitchen]])
        let world = await World.household(sonos, foundThrough: .kitchen, on: [(.livingRoom, 40), (.kitchen, 30)])
        world.music(seconds: 3)

        world.silence(seconds: 60)
        await settle()

        #expect(sonos.calls(to: .kitchen) == Calls.lead(volume: 30) + [Calls.stop])
        #expect(sonos.calls(to: .livingRoom) == Calls.join(.kitchen, volume: 40))
        #expect(sonos.transportState(of: .livingRoom) == "STOPPED")
    }
}
