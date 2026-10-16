import Foundation
import Testing
import PressingCore

@MainActor
@Suite("Taking over a Room")
struct TakeoverTests {
    /// The DIDL-Lite SoCo sends for a title-only radio station, titled "Pressing".
    private let didl = #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="R:0/0/0" parentID="R:0/0" restricted="true"><dc:title>Pressing</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item></DIDL-Lite>"#

    private var takeover: [SOAPCall] {
        [
            SOAPCall("SetAVTransportURI", [
                "InstanceID": "0",
                "CurrentURI": "x-rincon-mp3radio://192.168.1.50:8020/pressing/turntable.mp3",
                "CurrentURIMetaData": didl,
            ]),
            SOAPCall("SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "30"]),
            SOAPCall("Play", ["InstanceID": "0", "Speed": "1"]),
        ]
    }

    private let stop = SOAPCall("Stop", ["InstanceID": "0"])

    /// Rooms found, with the kitchen switched on at volume 30.
    private func household() async -> World {
        let world = World()
        world.sonos.discover(.livingRoom)
        await settle()
        world.pressing.switchRoom(FakeRoom.kitchen.uuid, on: true)
        world.pressing.setVolume(30, for: FakeRoom.kitchen.uuid)
        return world
    }

    @Test("Dropping the needle points the switched-on Room at the stream, sets its volume and plays")
    func needleDrop() async {
        let world = await household()

        world.music(seconds: 3)
        await settle()

        #expect(world.sonos.calls(to: .kitchen) == takeover)
        #expect(world.sonos.malformed.isEmpty)
    }

    @Test("A switched-off Room gets no requests")
    func switchedOffUntouched() async {
        let world = await household()

        world.music(seconds: 3)
        world.silence(seconds: 60)
        await settle()

        #expect(world.sonos.calls(to: .livingRoom).isEmpty)
    }

    @Test("Before the needle drops, nothing is sent")
    func nothingBeforeRecord() async {
        let world = await household()

        world.silence(seconds: 10)
        await settle()

        #expect(world.sonos.calls(to: .kitchen).isEmpty)
    }

    @Test("A Flip and the next Record keep the Room playing without a new Takeover")
    func flipKeepsPlaying() async {
        let world = await household()
        world.music(seconds: 3)

        world.silence(seconds: 20)
        world.music(seconds: 3)
        await settle()

        #expect(world.sonos.calls(to: .kitchen) == takeover)
    }

    @Test("When the Session ends, the Room gets Stop and nothing else")
    func sessionEnd() async {
        let world = await household()
        world.music(seconds: 3)

        world.silence(seconds: 60)
        await settle()

        #expect(world.pressing.state.session == .idle)
        #expect(world.sonos.calls(to: .kitchen) == takeover + [stop])
    }

    @Test("The next Session takes the Room over again")
    func nextSession() async {
        let world = await household()
        world.music(seconds: 3)
        world.silence(seconds: 60)

        world.music(seconds: 3)
        await settle()

        #expect(world.sonos.calls(to: .kitchen) == takeover + [stop] + takeover)
    }

    @Test("Changing the volume during a Session sets it on the Room at once")
    func volumeDuringSession() async {
        let world = await household()
        world.music(seconds: 3)

        world.pressing.setVolume(12, for: FakeRoom.kitchen.uuid)
        await settle()

        #expect(world.sonos.calls(to: .kitchen).last == SOAPCall("SetVolume", ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "12"]))
    }

    @Test("A Room that refuses the stream is not told to play, and the other switched-on Room still is")
    func refusedRoom() async {
        let world = await household()
        world.pressing.switchRoom(FakeRoom.livingRoom.uuid, on: true)
        world.pressing.setVolume(30, for: FakeRoom.livingRoom.uuid)
        world.sonos.faults[FakeRoom.kitchen.host] = 714

        world.music(seconds: 3)
        await settle()

        #expect(world.sonos.calls(to: .kitchen).map(\.action) == ["SetAVTransportURI"])
        #expect(world.sonos.calls(to: .livingRoom) == takeover)
    }
}
