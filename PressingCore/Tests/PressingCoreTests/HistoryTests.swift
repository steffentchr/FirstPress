import Foundation
import Testing
import PressingCore

@MainActor
@Suite("History")
struct HistoryTests {
    @Test("A Play is kept from the moment it starts: no album yet, and not scrobbled")
    func keptFromStart() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]

        world.music(seconds: 12)
        await settle()

        let current = try #require(world.pressing.state.play)
        let stored = try #require(world.store.plays.last)
        #expect(stored == current)
        #expect(stored.endedAt == nil)
        #expect(stored.track.album == nil)
        #expect(stored.scrobble == .notScrobbled)
        #expect(world.pressing.history == [current])
    }

    @Test("The Play kept at its start is updated, not duplicated, when it ends")
    func updatedAtEnd() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]

        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        await settle()

        #expect(world.store.plays.count == 1)
        let ended = try #require(world.store.plays.first?.endedAt)
        #expect(world.pressing.history.count == 1)
        #expect(world.pressing.history.first?.endedAt == ended)
    }

    @Test("Plays survive a restart, newest first")
    func surviveRestart() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        await settle()

        let restarted = Pressing(audioInput: FakeAudioInput(), store: world.store, scheduler: FakeScheduler())
        restarted.start()

        #expect(restarted.history.map(\.track) == [.rocker, .ballad])
        #expect(restarted.history.allSatisfy { $0.endedAt != nil })
    }

    @Test("A Play's cover is downloaded once and kept on the phone")
    func coverKept() async throws {
        let world = World()
        let artwork = try #require(Track.ballad.artworkURL)
        world.artwork.covers[artwork] = Data("ballad cover".utf8)
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(world.pressing.history.count == 2)
        #expect(world.artwork.downloads == [artwork])
        #expect(world.pressing.cover(for: .ballad) == Data("ballad cover".utf8))

        let restarted = Pressing(audioInput: FakeAudioInput(), store: world.store, scheduler: FakeScheduler())
        restarted.start()
        #expect(restarted.cover(for: .ballad) == Data("ballad cover".utf8))
    }

    @Test("A Track with no artwork, or whose download fails, has no cover")
    func noCover() async throws {
        let world = World()
        world.recognizer.answers = [.match(.rocker, offset: 2)]
        world.music(seconds: 12)
        await settle()
        world.silence(seconds: 15)
        // The fake has no cover for the ballad's URL, so its download fails.
        world.recognizer.answers = [.match(.ballad, offset: 2)]
        world.music(seconds: 12)
        await settle()

        #expect(world.artwork.downloads == [Track.ballad.artworkURL])
        #expect(world.pressing.cover(for: .rocker) == nil)
        #expect(world.pressing.cover(for: .ballad) == nil)
    }
}
