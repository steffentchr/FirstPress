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
}
