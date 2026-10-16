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

    @Test("A Track played more than once is listed once, at its most recent Play, and not at all while it's the current Play")
    func noDuplicates() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func play(_ title: String, minute: Double) -> Play {
            Play(track: Track(artist: "Artist", title: title), startedAt: start + minute * 60, endedAt: start + minute * 60 + 50)
        }
        // Newest first, as History keeps them.
        let history = [play("C", minute: 4), play("a", minute: 3), play("B", minute: 2), play("A", minute: 1)]

        #expect(Pressing.recentPlays(in: history, excluding: nil).map(\.track.title) == ["C", "a", "B"])

        let current = play("A", minute: 5)
        #expect(Pressing.recentPlays(in: [current] + history, excluding: current.id).map(\.track.title) == ["C", "B"])
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
