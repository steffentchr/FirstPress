import Foundation
import Testing
import FirstPressCore
import FirstPressMenuCore

@MainActor
@Suite("First Press Menu without local network access")
struct FirstPressMenuLocalNetworkTests {
    @Test("Without local network access, First Press Menu asks to be allowed on the local network instead of looking for First Press")
    func asksForLocalNetwork() {
        let world = World()
        let (menu, _) = world.firstPressMenu(localNetworkDenied: true)

        #expect(menu.connection == .looking)
        #expect(menu.header == .allowLocalNetwork)
        #expect(!menu.showsLookingLine)
    }

    @Test("Once it's allowed on the local network, First Press Menu finds First Press and connects, and stops asking")
    func connectsOnceAllowed() {
        let world = World()
        let (menu, link) = world.firstPressMenu(localNetworkDenied: true)
        world.scheduler.advance(by: 600)
        #expect(menu.header == .allowLocalNetwork)

        link.isLocalNetworkDenied = false
        #expect(menu.connection == .connected)
        #expect(menu.header == .waitingForRecord)

        // A later drop-out says it's looking again, not that it needs access.
        world.menuServer.stop()
        #expect(menu.header == .lookingForFirstPress)
    }

    @Test("Losing local network access after a drop-out asks for it in place of looking: in the header, or in the line beneath a kept Track")
    func asksAfterDropOut() async {
        let world = World()
        let (menu, link) = world.firstPressMenu()
        #expect(menu.header == .waitingForRecord)

        link.isLocalNetworkDenied = true
        world.menuServer.stop()
        // The next attempt, a second later, finds it isn't allowed.
        world.scheduler.advance(by: 1)
        #expect(menu.header == .allowLocalNetwork)
        #expect(!menu.showsLookingLine)
        #expect(!menu.showsLocalNetworkLine)

        link.isLocalNetworkDenied = false
        world.menuServer.start()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        #expect(menu.header == .track(.ballad))
        #expect(!menu.showsLocalNetworkLine)

        link.isLocalNetworkDenied = true
        world.menuServer.stop()
        world.scheduler.advance(by: 1)
        #expect(menu.header == .track(.ballad))
        #expect(menu.showsLocalNetworkLine)
        #expect(!menu.showsLookingLine)

        link.isLocalNetworkDenied = false
        world.menuServer.start()
        world.scheduler.advance(by: 1)
        #expect(menu.connection == .connected)
        #expect(!menu.showsLocalNetworkLine)
    }
}
