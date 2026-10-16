import Foundation
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

    @Test("At most the 50 most recent Plays are listed; older ones stay kept")
    func fiftyMostRecent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // Saved oldest first; minute i is the i-th Play.
        let plays = (0..<60).map { i in
            Play(track: Track(artist: "Artist", title: "Track \(i)"), startedAt: start + Double(i) * 60, endedAt: start + Double(i) * 60 + 50)
        }
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: plays))

        #expect(world.pressing.history.count == 60)
        #expect(world.pressing.recentPlays.count == 50)
        #expect(world.pressing.recentPlays.first?.track.title == "Track 59")
        #expect(world.pressing.recentPlays.last?.track.title == "Track 10")
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
