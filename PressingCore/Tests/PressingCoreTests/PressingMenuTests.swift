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

    /// Plays from last night, saved oldest first: "Track 0" to "Track \(count - 1)".
    private func lastNight(_ count: Int) -> [Play] {
        let start = Date(timeIntervalSince1970: 1_699_900_000)
        return (0..<count).map { i in
            Play(track: Track(artist: "Artist", title: "Track \(i)"), startedAt: start + Double(i) * 240, endedAt: start + Double(i) * 240 + 200)
        }
    }
}
