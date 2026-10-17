import Foundation
import Testing
import FirstPressCore

/// A Play starts at the latest of: the start worked back from the match, the
/// start of the Record, and the end of the previous Play.
@MainActor
@Suite("Play start time")
struct PlayStartTests {
    @Test("A needle dropped mid-Track starts the Play at the Record start, not two minutes before it")
    func needleDroppedMidTrack() async throws {
        let world = World()
        let needleDrop = world.scheduler.now
        world.recognizer.answers = [.match(.ballad, offset: 120)]

        world.music(seconds: 12)
        await settle()

        let play = try #require(world.firstPress.state.play)
        #expect(abs(play.startedAt.timeIntervalSince(needleDrop)) < 1)
    }

    @Test("A Track picked up by a recheck starts where the match puts it, and the previous Play ends there")
    func startWorkedBackFromMatch() async throws {
        let world = World()
        let needleDrop = world.scheduler.now
        // The recheck's audio starts about 32 s in, 5 s into the second Track.
        world.recognizer.answers = [.match(.ballad, offset: 2), .match(.rocker, offset: 5)]

        world.music(seconds: 45)
        await settle()

        let rocker = try #require(world.firstPress.state.play)
        #expect(rocker.track == .rocker)
        #expect(abs(rocker.startedAt.timeIntervalSince(needleDrop) - 27) < 1.5)
        let ballad = try #require(world.store.endedPlays.last)
        #expect(ballad.endedAt == rocker.startedAt)
    }

    @Test("A Play never starts before the previous Play ended")
    func notBeforePreviousEnd() async throws {
        let world = World()
        let needleDrop = world.scheduler.now
        // The ballad ends at the Gap 12 s in after two misses; the rocker's
        // match would put its start well before the Record.
        world.recognizer.answers = [.match(.ballad, offset: 2), .noMatch, .noMatch, .match(.rocker, offset: 100)]

        world.music(seconds: 12)
        world.silence(seconds: 3)
        world.music(seconds: 70)
        await settle()

        let rocker = try #require(world.firstPress.state.play)
        #expect(rocker.track == .rocker)
        let ballad = try #require(world.store.endedPlays.last)
        #expect(ballad.track == .ballad)
        #expect(rocker.startedAt == ballad.endedAt)
        #expect(abs(rocker.startedAt.timeIntervalSince(needleDrop) - 12) < 1)
    }
}
