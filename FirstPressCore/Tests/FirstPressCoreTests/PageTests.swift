import Testing
import FirstPressCore

@MainActor
@Suite("Which page shows")
struct PageTests {
    @Test("With no input chosen, First Press asks for one and starts nothing else")
    func noInputChosen() {
        let world = World(settings: Settings())

        world.music(seconds: 5)

        #expect(world.firstPress.state.page == .chooseInput(.noneChosen))
        #expect(world.input.startedInputs.isEmpty)
        #expect(world.sonos.network.isDiscovering == false)
        #expect(world.sink.listeningPort == nil)
        #expect(world.recognizer.searches.isEmpty)
    }

    @Test("Choosing an input moves on to waiting and starts everything")
    func choosingStarts() {
        let world = World(settings: Settings())

        world.firstPress.chooseInput(AudioInputDevice.deck.id)

        #expect(world.firstPress.state.page == .waiting)
        #expect(world.input.startedInputs == ["usb-deck"])
        #expect(world.sonos.network.isDiscovering == true)
        #expect(world.sink.listeningPort == FirstPress.streamPort)
    }

    @Test("With the chosen input unplugged and no Session, First Press asks for it; plugging it back in returns to waiting")
    func unplugWhileWaiting() {
        let world = World()
        #expect(world.firstPress.state.page == .waiting)

        world.input.unplug(AudioInputDevice.deck.id)
        #expect(world.firstPress.state.page == .chooseInput(.notConnected))
        // Rooms stay known meanwhile.
        #expect(world.sonos.network.isDiscovering == true)
        #expect(world.sink.listeningPort == FirstPress.streamPort)

        world.input.plugIn(.deck)
        #expect(world.firstPress.state.page == .waiting)
    }

    @Test("A Record starting shows Now Playing; it stays through a Gap and a Flip, and waiting returns when the Session ends")
    func nowPlayingFollowsTheSession() {
        let world = World()

        world.music(seconds: 5)
        #expect(world.firstPress.state.page == .nowPlaying)

        world.silence(seconds: 3)
        #expect(world.firstPress.state.session == .running(records: 1, record: .gap))
        #expect(world.firstPress.state.page == .nowPlaying)

        world.silence(seconds: 15)
        #expect(world.firstPress.state.session == .running(records: 1, record: .flipped))
        #expect(world.firstPress.state.page == .nowPlaying)

        world.silence(seconds: 30)
        #expect(world.firstPress.state.session == .idle)
        #expect(world.firstPress.state.page == .waiting)
    }

    @Test("Unplugging mid-Session keeps Now Playing until the Session ends, then asks for the input")
    func unplugMidSession() {
        let world = World()
        world.music(seconds: 5)

        world.input.unplug(AudioInputDevice.deck.id)
        #expect(world.firstPress.state.page == .nowPlaying)

        world.scheduler.advance(by: 60)
        #expect(world.firstPress.state.session == .idle)
        #expect(world.firstPress.state.page == .chooseInput(.notConnected))
    }
}
