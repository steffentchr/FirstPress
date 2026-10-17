import Foundation
import Testing
import FirstPressCore
import FirstPressMenuCore

@MainActor
@Suite("First Press Menu")
struct FirstPressMenuTests {
    @Test("First Press Menu shows the current Track once one is identified, and updates when the next one is")
    func showsCurrentTrack() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()

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

    @Test("The header's Track gains its album when Last.fm names it a moment later, and keeps it after a drop-out")
    func albumArrivesLater() async throws {
        let world = World(lastFm: .listener)
        let (menu, _) = world.firstPressMenu()
        world.lastFm.knows(.ballad, durationMilliseconds: 268_000, album: "The Kick Inside")

        try await world.identify(.ballad)

        guard case .track(let track) = menu.header else {
            Issue.record("Expected a Track, got \(menu.header)")
            return
        }
        #expect(track.title == "Wuthering Heights")
        #expect(track.album == "The Kick Inside")

        world.menuServer.stop()
        #expect(menu.header == .track(track))
    }

    @Test("With no Session running, First Press Menu says First Press is waiting for a Record")
    func waiting() {
        let world = World()
        let (menu, _) = world.firstPressMenu()

        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("A Record playing that isn't identified yet says so, and after its Flip no Record is playing")
    func recordNotIdentified() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()

        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .recordNotIdentified)
        #expect(menu.isRecordPlaying)

        world.silence(seconds: 15)
        await settle()
        #expect(menu.header == .betweenSides(lastTrack: nil))
        #expect(!menu.isRecordPlaying)
    }

    @Test("After a Flip the header says Between sides, with the last Track beneath, until the next Record starts")
    func betweenSides() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 15)
        await settle()
        #expect(world.firstPress.state.session == .running(records: 1, record: .flipped))
        #expect(menu.header == .betweenSides(lastTrack: .ballad))

        world.music(seconds: 5)
        await settle()
        #expect(menu.header == .recordNotIdentified)
    }

    @Test("Between sides ends with the Session: then First Press is waiting for a Record")
    func betweenSidesUntilSessionEnds() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 15)
        await settle()
        #expect(menu.header == .betweenSides(lastTrack: .ballad))

        world.silence(seconds: 40)
        await settle()
        #expect(world.firstPress.state.session == .idle)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("Between sides names no Track when none was identified in the Session, not even one from an earlier Session")
    func betweenSidesWithoutTrack() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 60)
        await settle()
        #expect(world.firstPress.state.session == .idle)

        world.recognizer.answers = []
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        await settle()
        #expect(menu.header == .betweenSides(lastTrack: nil))
    }

    @Test("A phone that doesn't send the last Track still shows Between sides after a Flip")
    func betweenSidesFromOlderPhone() {
        let world = World()
        let (menu, link) = world.firstPressMenu()

        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "nowPlaying", "record": "flipped", "recentPlays": []}"#)

        #expect(menu.header == .betweenSides(lastTrack: nil))
    }

    @Test("The phone's input pages show as waiting for a Record")
    func inputPagesShowAsWaiting() {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        let sentBefore = world.menuServer.sentCount

        world.input.unplug(AudioInputDevice.deck.id)

        #expect(world.firstPress.state.page == .chooseInput(.notConnected))
        #expect(world.menuServer.sentCount == sentBefore + 1)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("First Press Menu says it's looking for First Press until it finds it, however long that takes")
    func lookingUntilFound() {
        // No input chosen yet: the phone hasn't started its services, so
        // nothing is advertised on the network.
        let world = World(settings: Settings())
        let (menu, _) = world.firstPressMenu()
        #expect(menu.connection == .looking)
        #expect(menu.header == .lookingForFirstPress)

        world.scheduler.advance(by: 600)
        #expect(menu.connection == .looking)
        #expect(menu.header == .lookingForFirstPress)
        #expect(!menu.showsLookingLine)

        world.firstPress.chooseInput(AudioInputDevice.deck.id)
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("Connecting that fails before First Press was ever reached keeps First Press Menu looking, and it tries again")
    func failedFirstAttemptKeepsLooking() {
        let world = World()
        world.menuServer.refusesConnections = true
        let (menu, link) = world.firstPressMenu()
        #expect(link.connectAttempts == 1)
        #expect(menu.connection == .looking)
        #expect(menu.header == .lookingForFirstPress)

        world.scheduler.advance(by: 1)
        #expect(link.connectAttempts == 2)
        #expect(menu.connection == .looking)

        world.menuServer.refusesConnections = false
        world.scheduler.advance(by: 2)
        #expect(menu.connection == .connected)
    }

    @Test("First Press Menu lists the last 10 different Tracks, newest first, outside a Session too")
    func historyOutsideSession() {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(12)))
        let (menu, _) = world.firstPressMenu()

        #expect(menu.header == .waitingForRecord)
        #expect(menu.history.map(\.title) == (2...11).reversed().map { "Track \($0)" })
        #expect(menu.history.first?.artist == "Artist")
    }

    @Test("First Press Menu leaves the current Play out, and lists a Track played last night and again tonight once, at tonight's place")
    func historyRules() async {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(12)))
        let (menu, _) = world.firstPressMenu()

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

    @Test("Level meter updates send First Press Menu no snapshot")
    func levelUpdatesSendNothing() {
        let world = World()
        _ = world.firstPressMenu()
        let sentOnConnect = world.menuServer.sentCount
        #expect(sentOnConnect == 1)

        // Quiet hiss from the deck: the level moves, nothing else does.
        world.play(Signal.square(amplitude: 0.002, seconds: 3, sampleRate: 44_100))

        #expect(world.firstPress.state.input.level != nil)
        #expect(world.menuServer.sentCount == sentOnConnect)
    }

    @Test("Two First Press Menus connected at once both get snapshots")
    func twoFirstPressMenus() async {
        let world = World()
        let (first, _) = world.firstPressMenu()
        let (second, _) = world.firstPressMenu()

        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(first.header == .track(.ballad))
        #expect(second.header == .track(.ballad))
    }

    @Test("A dropped link keeps the last Track and History on screen, and First Press Menu reconnects by itself")
    func droppedLinkKeepsSnapshot() async {
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: lastNight(3)))
        let (menu, link) = world.firstPressMenu()
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

    @Test("After a drop-out with a Track kept on screen, a small line beneath the greyed Track says First Press Menu is looking for First Press")
    func lookingBeneathKeptTrack() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(!menu.showsLookingLine)

        world.menuServer.stop()
        #expect(menu.header == .track(.ballad))
        #expect(menu.showsLookingLine)

        world.menuServer.start()
        world.scheduler.advance(by: 1)
        #expect(menu.connection == .connected)
        #expect(menu.header == .track(.ballad))
        #expect(!menu.showsLookingLine)
    }

    @Test("After a drop-out with no Track kept, the header says only that First Press Menu is looking for First Press, and no line repeats it")
    func lookingInHeaderOnly() async {
        let world = World()
        let (menu, _) = world.firstPressMenu()
        #expect(menu.header == .waitingForRecord)

        world.menuServer.stop()
        #expect(menu.header == .lookingForFirstPress)
        #expect(!menu.showsLookingLine)

        // Between sides isn't kept either: only a Track is.
        world.menuServer.start()
        world.scheduler.advance(by: 1)
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        await settle()
        #expect(menu.header == .betweenSides(lastTrack: nil))
        world.menuServer.stop()
        #expect(menu.header == .lookingForFirstPress)
    }

    @Test("While First Press isn't running First Press Menu says it's looking for First Press, and finds it again when it is")
    func phoneGoneAndBack() {
        let world = World()
        let (menu, _) = world.firstPressMenu()

        world.menuServer.stop()
        #expect(menu.connection == .cantBeReached)
        #expect(menu.header == .lookingForFirstPress)

        world.scheduler.advance(by: 60)
        #expect(menu.connection == .cantBeReached)

        world.menuServer.start()
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)
    }

    @Test("When connecting fails, First Press Menu tries again after 1, 2, 4 and 8 seconds, then no more often than every 30 seconds")
    func reconnectBackoff() {
        let world = World()
        let (menu, link) = world.firstPressMenu()
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

    @Test("First Press Menu ignores snapshot fields it doesn't know, from a newer phone of the same major version")
    func ignoresUnknownFields() {
        let world = World()
        let (menu, link) = world.firstPressMenu()

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

    @Test("Only a newer major version shows Update First Press Menu")
    func newerMajorVersion() {
        let world = World()
        let (menu, link) = world.firstPressMenu()

        link.deliver(json: #"{"type": "snapshot", "major": 1, "page": "waiting", "recentPlays": []}"#)
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)

        link.deliver(json: #"{"type": "snapshot", "major": 2, "everything": "different"}"#)
        #expect(menu.connection == .needsUpdate)
        #expect(menu.header == .updateFirstPressMenu)
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
