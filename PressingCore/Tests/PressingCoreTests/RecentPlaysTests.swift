import Testing
import PressingCore

@MainActor
@Suite("Recently played on Now Playing")
struct RecentPlaysTests {
    @Test("Recently played is History without the current Play, newest first")
    func excludesCurrentPlay() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(world.pressing.state.play?.track == .rocker)
        #expect(world.pressing.history.map(\.track) == [.rocker, .ballad])
        #expect(world.pressing.recentPlays.map(\.track) == [.ballad])
    }

    @Test("After a Flip, with no current Play, the Play that just ended is listed")
    func afterFlip() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        await settle()

        #expect(world.pressing.state.page == .nowPlaying)
        #expect(world.pressing.state.play == nil)
        #expect(world.pressing.recentPlays.map(\.track) == [.ballad])
    }
}
