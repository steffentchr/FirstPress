import Foundation
import Testing
import PressingCore

@MainActor
@Suite("Identification")
struct IdentificationTests {
    private let rate = 44_100.0

    @Test("A Record starting runs one search on mono audio of the deck")
    func searchOnRecordStart() async throws {
        let world = World()

        // Left and right differ, so a test can tell the mix from one side.
        let left = Signal.square(amplitude: 0.1, seconds: 12, sampleRate: rate)
        world.playStereo(left: left, right: left.map { $0 * 3 })
        await settle()

        let search = try #require(world.recognizer.searches.first)
        #expect(world.recognizer.searches.count == 1)
        #expect(search.sampleRate == rate)
        #expect(search.seconds >= 5 && search.seconds <= 12)
        #expect(search.samples.allSatisfy { abs(abs($0) - 0.2) < 0.0001 })
    }

    @Test("A match puts the Track in the lower third")
    func matchShowsTrack() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30)]

        world.music(seconds: 12)
        await settle()

        #expect(world.pressing.state.play?.track == .ballad)
    }

    @Test("After a Gap, a search runs on the music that follows it")
    func searchAfterGap() async throws {
        let world = World()

        world.music(seconds: 12)
        world.silence(seconds: 3)
        world.music(seconds: 12)
        await settle()

        #expect(world.recognizer.searches.count == 2)
        let afterGap = try #require(world.recognizer.searches.last)
        #expect(afterGap.samples.allSatisfy { abs(abs($0) - 0.1) < 0.0001 })
    }

    @Test("Without a Gap, a recheck runs every 30 s")
    func recheck() async {
        let world = World()

        world.music(seconds: 30)
        await settle()
        #expect(world.recognizer.searches.count == 1)

        world.music(seconds: 15)
        await settle()
        #expect(world.recognizer.searches.count == 2)

        world.music(seconds: 30)
        await settle()
        #expect(world.recognizer.searches.count == 3)
    }

    @Test("A search after a Gap puts the recheck off for 30 s")
    func gapPutsOffRecheck() async {
        let world = World()

        world.music(seconds: 12)
        world.silence(seconds: 3)
        world.music(seconds: 30)
        await settle()

        #expect(world.recognizer.searches.count == 2)
    }

    @Test("No search runs while the deck is silent between Records")
    func noSearchWhenSilent() async {
        let world = World()

        world.music(seconds: 12)
        world.silence(seconds: 120)
        await settle()

        #expect(world.recognizer.searches.count == 1)
    }

    @Test("A Flip clears the lower third and ends the Play as of when the silence began")
    func flipEndsPlay() async throws {
        let world = World()
        let start = world.scheduler.now
        world.recognizer.answers = [.match(.ballad, offset: 30)]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 15)
        await settle()

        #expect(world.pressing.state.play == nil)
        let play = try #require(world.store.plays.last)
        #expect(play.track == .ballad)
        let ended = try #require(play.endedAt)
        #expect(abs(ended.timeIntervalSince(start) - 12) < 1)
    }

    @Test("An answer that arrives after the Flip doesn't bring the Track back")
    func lateAnswerIgnored() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30)]

        world.music(seconds: 11)
        world.silence(seconds: 15)
        await settle()

        #expect(world.recognizer.searches.count == 1)
        #expect(world.pressing.state.play == nil)
        #expect(world.store.plays.isEmpty)
    }

    @Test("A repeat match of the current Track continues its Play")
    func repeatContinues() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30), .match(.ballad, offset: 60), .match(.ballad, offset: 72)]
        world.music(seconds: 12)
        await settle()
        let first = try #require(world.pressing.state.play)

        world.music(seconds: 30)
        world.silence(seconds: 3)
        world.music(seconds: 12)
        await settle()

        #expect(world.recognizer.searches.count == 3)
        #expect(world.pressing.state.play == first)
        #expect(world.store.plays.isEmpty)
    }

    @Test("A different Track ends the current Play and starts a new one")
    func differentTrack() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30), .match(.rocker, offset: 10)]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 3)
        world.music(seconds: 12)
        await settle()

        let current = try #require(world.pressing.state.play)
        #expect(current.track == .rocker)
        #expect(world.store.plays.map(\.track) == [.ballad])
        #expect(world.store.plays.first?.endedAt == current.startedAt)
    }

    @Test("The Track stays through a Gap and a single miss")
    func singleMissKeeps() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30), .noMatch]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 3)
        #expect(world.pressing.state.play?.track == .ballad)
        world.music(seconds: 12)
        await settle()

        #expect(world.recognizer.searches.count == 2)
        #expect(world.pressing.state.play?.track == .ballad)
        #expect(world.store.plays.isEmpty)
    }

    @Test("A miss after a Gap and a miss on the next recheck end the Play as of the Gap")
    func doubleMissClears() async throws {
        let world = World()
        let start = world.scheduler.now
        world.recognizer.answers = [.match(.ballad, offset: 30), .noMatch, .noMatch]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 3)
        world.music(seconds: 45)
        await settle()

        #expect(world.recognizer.searches.count == 3)
        #expect(world.pressing.state.play == nil)
        let play = try #require(world.store.plays.last)
        let ended = try #require(play.endedAt)
        #expect(abs(ended.timeIntervalSince(start) - 12) < 1)
    }

    @Test("A recheck that misses without a Gap before it keeps the Track")
    func recheckMissAloneKeeps() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30), .noMatch, .noMatch]
        world.music(seconds: 75)
        await settle()

        #expect(world.recognizer.searches.count == 3)
        #expect(world.pressing.state.play?.track == .ballad)
    }

    @Test("A search that fails, rather than misses, doesn't count towards clearing the Track")
    func failureIsNotAMiss() async {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30), nil, .noMatch]
        world.music(seconds: 12)
        await settle()

        world.silence(seconds: 3)
        world.music(seconds: 45)
        await settle()

        #expect(world.recognizer.searches.count == 3)
        #expect(world.pressing.state.play?.track == .ballad)
    }
}

extension Track {
    static let ballad = Track(artist: "Kate Bush", title: "Wuthering Heights", artworkURL: URL(string: "https://example.com/ballad.jpg"))
    static let rocker = Track(artist: "Gasolin'", title: "Rabalderstræde")
}

extension World {
    /// Plays a stereo deck in real time, in 512-frame buffers.
    func playStereo(left: [Float], right: [Float], sampleRate: Double = 44_100) {
        var start = 0
        while start < left.count {
            let end = min(start + 512, left.count)
            scheduler.advance(by: Double(end - start) / sampleRate)
            input.send(.buffer(PCMBuffer(
                inputID: AudioInputDevice.deck.id,
                sampleRate: sampleRate,
                time: Double(start) / sampleRate,
                channels: [Array(left[start..<end]), Array(right[start..<end])]
            )))
            start = end
        }
    }
}
