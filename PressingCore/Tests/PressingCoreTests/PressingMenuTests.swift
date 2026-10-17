import Foundation
import Testing
import PressingCore
import PressingMenuCore

@MainActor
@Suite("Pressing Menu")
struct PressingMenuTests {
    @Test("Pressing Menu shows the current Track once one is identified, and updates when the next one is")
    func showsCurrentTrack() async {
        let world = World()
        let (menu, _) = world.pressingMenu()

        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .track(.ballad))

        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .track(.rocker))
    }

    @Test("With no Session running, Pressing Menu says Pressing is waiting for a Record")
    func waiting() {
        let world = World()
        let (menu, _) = world.pressingMenu()

        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("A Record playing that isn't identified yet says so, and after its Flip Pressing is waiting again")
    func recordNotIdentified() async {
        let world = World()
        let (menu, _) = world.pressingMenu()

        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .recordNotIdentified)
        #expect(menu.isRecordPlaying)

        world.silence(seconds: 15)
        await settle()
        #expect(menu.header == .waitingForRecord)
        #expect(!menu.isRecordPlaying)
    }

    @Test("The phone's input pages show as waiting for a Record")
    func inputPagesShowAsWaiting() {
        let world = World()
        let (menu, _) = world.pressingMenu()
        let sentBefore = world.menuServer.sentCount

        world.input.unplug(AudioInputDevice.deck.id)

        #expect(world.pressing.state.page == .chooseInput(.notConnected))
        #expect(world.menuServer.sentCount == sentBefore + 1)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("Pressing Menu is looking for Pressing until it finds it, and says the iPhone can't be reached after a while")
    func lookingThenCantBeReached() {
        // No input chosen yet: the phone hasn't started its services, so
        // nothing is advertised on the network.
        let world = World(settings: Settings())
        let (menu, _) = world.pressingMenu()
        #expect(menu.connection == .looking)
        #expect(menu.header == .lookingForPressing)

        world.scheduler.advance(by: PressingMenu.lookingFor)
        #expect(menu.connection == .cantBeReached)
        #expect(menu.header == .cantBeReached)

        world.pressing.chooseInput(AudioInputDevice.deck.id)
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("Pressing Menu lists the last 10 different Tracks, newest first, outside a Session too")
    func historyOutsideSession() {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(12)))
        let (menu, _) = world.pressingMenu()

        #expect(menu.header == .waitingForRecord)
        #expect(menu.history.map(\.title) == (2...11).reversed().map { "Track \($0)" })
        #expect(menu.history.first?.artist == "Artist")
    }

    @Test("Pressing Menu leaves the current Play out, and lists a Track played last night and again tonight once, at tonight's place")
    func historyRules() async {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(12)))
        let (menu, _) = world.pressingMenu()

        world.recognizer.answers = [.match(Track(artist: "Artist", title: "Track 5"), offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(menu.header == .track(.rocker))
        #expect(menu.history.map(\.title) == ["Track 5", "Track 11", "Track 10", "Track 9", "Track 8", "Track 7", "Track 6", "Track 4", "Track 3", "Track 2"])
    }

    @Test("Level meter updates send Pressing Menu no snapshot")
    func levelUpdatesSendNothing() {
        let world = World()
        _ = world.pressingMenu()
        let sentOnConnect = world.menuServer.sentCount
        #expect(sentOnConnect == 1)

        // Quiet hiss from the deck: the level moves, nothing else does.
        world.play(Signal.square(amplitude: 0.002, seconds: 3, sampleRate: 44_100))

        #expect(world.pressing.state.input.level != nil)
        #expect(world.menuServer.sentCount == sentOnConnect)
    }

    @Test("Two Pressing Menus connected at once both get snapshots")
    func twoPressingMenus() async {
        let world = World()
        let (first, _) = world.pressingMenu()
        let (second, _) = world.pressingMenu()

        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(first.header == .track(.ballad))
        #expect(second.header == .track(.ballad))
    }

    @Test("A dropped link keeps the last Track and History on screen, and Pressing Menu reconnects by itself")
    func droppedLinkKeepsSnapshot() async {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(3)))
        let (menu, link) = world.pressingMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        link.drop()
        #expect(menu.connection == .cantBeReached)
        #expect(menu.header == .track(.ballad))
        #expect(menu.history.map(\.title) == ["Track 2", "Track 1", "Track 0"])

        world.scheduler.advance(by: 1)
        #expect(menu.connection == .connected)
        #expect(menu.header == .track(.ballad))
    }

    @Test("While Pressing isn't running Pressing Menu says the iPhone can't be reached, and finds it again when it is")
    func phoneGoneAndBack() {
        let world = World()
        let (menu, _) = world.pressingMenu()

        world.menuServer.stop()
        #expect(menu.connection == .cantBeReached)
        #expect(menu.header == .cantBeReached)

        world.scheduler.advance(by: 60)
        #expect(menu.connection == .cantBeReached)

        world.menuServer.start()
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("When connecting fails, Pressing Menu tries again after 1, 2, 4 and 8 seconds, then no more often than every 30 seconds")
    func reconnectBackoff() {
        let world = World()
        let (menu, link) = world.pressingMenu()
        world.menuServer.refusesConnections = true
        link.drop()
        #expect(link.connectAttempts == 1)

        for (wait, attempts) in [(1.0, 2), (2, 3), (4, 4), (8, 5), (16, 6), (30, 7), (30, 8)] {
            world.scheduler.advance(by: wait - 0.1)
            #expect(link.connectAttempts == attempts - 1)
            world.scheduler.advance(by: 0.1)
            #expect(link.connectAttempts == attempts)
        }
        #expect(menu.connection == .cantBeReached)

        world.menuServer.refusesConnections = false
        world.scheduler.advance(by: 30)
        #expect(menu.connection == .connected)

        // Connected again: the next drop starts over at 1 second.
        link.drop()
        world.scheduler.advance(by: 1)
        #expect(menu.connection == .connected)
    }

    @Test("Pressing Menu ignores snapshot fields it doesn't know, from a newer phone of the same major version")
    func ignoresUnknownFields() {
        let world = World()
        let (menu, link) = world.pressingMenu()

        link.deliver(json: """
            {"type": "snapshot", "major": 1, "minor": 7, "page": "nowPlaying", "record": "playing",
             "track": {"artist": "Kate Bush", "title": "Wuthering Heights", "duration": 268},
             "recentPlays": [{"track": {"artist": "Gasolin'", "title": "Rabalderstræde"}, "startedAt": "2026-10-16T21:04:00Z", "scrobbled": true}],
             "lyrics": {"line": "Out on the wiley, windy moors"}}
            """)

        #expect(menu.connection == .connected)
        #expect(menu.header == .track(Track(artist: "Kate Bush", title: "Wuthering Heights")))
        #expect(menu.history == [Track(artist: "Gasolin'", title: "Rabalderstræde")])
    }

    @Test("Only a newer major version shows Update Pressing Menu")
    func newerMajorVersion() {
        let world = World()
        let (menu, link) = world.pressingMenu()

        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "waiting", "recentPlays": []}"#)
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)

        link.deliver(json: #"{"type": "snapshot", "major": 2, "everything": "different"}"#)
        #expect(menu.connection == .needsUpdate)
        #expect(menu.header == .updatePressingMenu)
        #expect(menu.history.isEmpty)
    }

    /// Plays from last night, saved oldest first: "Track 0" to "Track \(count - 1)".
    private func lastNight(_ count: Int) -> [Play] {
        let start = Date(timeIntervalSince1970: 1_699_900_000)
        return (0..<count).map { i in
            Play(track: Track(artist: "Artist", title: "Track \(i)"), startedAt: start + Double(i) * 240, endedAt: start + Double(i) * 240 + 200)
        }
    }
}
