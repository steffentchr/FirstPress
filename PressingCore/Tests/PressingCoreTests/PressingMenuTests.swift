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
}
