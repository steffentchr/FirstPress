import Foundation
import Testing
import PressingCore

/// Now playing, the album from track.getInfo, and when a Play qualifies.
@MainActor
@Suite("Scrobbling")
struct ScrobblingTests {
    @Test("A new Play sends now playing, then asks track.getInfo")
    func nowPlayingThenGetInfo() async throws {
        let world = World(lastFm: .listener)

        try await world.identify(.ballad)

        #expect(world.lastFm.calls.map(\.method) == ["track.updateNowPlaying", "track.getInfo"])
        let nowPlaying = try #require(world.lastFm.calls("track.updateNowPlaying").first)
        #expect(nowPlaying.httpMethod == "POST")
        #expect(nowPlaying.params["artist"] == "Kate Bush")
        #expect(nowPlaying.params["track"] == "Wuthering Heights")
        #expect(nowPlaying.params["sk"] == "SESSIONKEY")
        #expect(nowPlaying.params["api_sig"]?.count == 32)
        let getInfo = try #require(world.lastFm.calls("track.getInfo").first)
        #expect(getInfo.httpMethod == "GET")
        #expect(getInfo.params["artist"] == "Kate Bush")
        #expect(getInfo.params["track"] == "Wuthering Heights")
        #expect(getInfo.params["sk"] == nil)
    }

    @Test("The album Last.fm knows fills in the Play, on screen and in History")
    func albumFromGetInfo() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 268_000, album: "The Kick Inside")

        let play = try await world.identify(.ballad)

        #expect(world.pressing.state.play?.track.album == "The Kick Inside")
        #expect(world.pressing.history.first?.track.album == "The Kick Inside")
        #expect(world.store.plays.first { $0.id == play.id }?.track.album == "The Kick Inside")
    }

    @Test("A Play made while connected is pending; one made while disconnected is not scrobbled and sends nothing")
    func statusAtStart() async throws {
        let connected = World(lastFm: .listener)
        #expect(try await connected.identify(.ballad).scrobble == .pending)

        let disconnected = World()
        let play = try await disconnected.identify(.ballad)
        #expect(play.scrobble == .notScrobbled)
        #expect(play.track.album == nil)
        #expect(disconnected.lastFm.requests.isEmpty)
    }

    @Test("A Track of known length qualifies at half its length")
    func qualifiesAtHalf() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)

        world.playFor(149, since: play)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").isEmpty)

        world.playFor(151, since: play)
        await settle()
        let scrobble = try #require(world.lastFm.calls("track.scrobble").first)
        #expect(scrobble.scrobbles.count == 1)
        #expect(scrobble.scrobbles.first?.artist == "Kate Bush")
        #expect(scrobble.scrobbles.first?.track == "Wuthering Heights")
        #expect(scrobble.scrobbles.first?.timestamp == String(Int(play.startedAt.timeIntervalSince1970)))
        #expect(scrobble.params["sk"] == "SESSIONKEY")
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
        #expect(world.store.plays.first?.scrobble == .scrobbled)
    }

    @Test("A long Track qualifies at 4 minutes, not half its length")
    func qualifiesAt240() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 600_000)
        let play = try await world.identify(.ballad)

        world.playFor(239, since: play)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").isEmpty)

        world.playFor(241, since: play)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").count == 1)
    }

    @Test("A Track of 30 s or less is never scrobbled, however long it plays")
    func tooShortTrack() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 30_000)
        let play = try await world.identify(.ballad)

        world.playFor(40, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        #expect(world.pressing.history.first?.scrobble == .notEligible)
    }

    @Test("A Track just over 30 s qualifies at half its length")
    func justOver30() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 31_000)
        let play = try await world.identify(.ballad)

        world.playFor(16, since: play)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").count == 1)
    }

    @Test("A Play that ends before half the length is not eligible")
    func endsTooSoon() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)

        world.playFor(100, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        let ended = try #require(world.pressing.history.first)
        #expect(ended.endedAt != nil)
        #expect(ended.scrobble == .notEligible)
        #expect(world.store.plays.first?.scrobble == .notEligible)
    }

    @Test("A Play whose Record goes silent before half the length is not eligible, though the Flip comes after it")
    func silenceBeforeQualifyingFlipAfter() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)

        // Silent from 140 s; the Flip, 12 s later, ends the Play as of 140 s.
        world.playFor(140, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        let ended = try #require(world.pressing.history.first)
        #expect(try #require(ended.endedAt).timeIntervalSince(ended.startedAt) < 150)
        #expect(ended.scrobble == .notEligible)
    }

    @Test("A Play that the search after a Gap and the recheck both miss is judged by when that Gap began")
    func doubleMissBeforeQualifying() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)

        // A Gap at 140 s; the music comes back, but neither the search after
        // the Gap nor the recheck finds anything.
        world.playFor(140, since: play)
        world.silence(seconds: 3)
        world.recognizer.answers = [.noMatch, .noMatch]
        world.music(seconds: 45)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        let ended = try #require(world.pressing.history.first)
        #expect(try #require(ended.endedAt).timeIntervalSince(ended.startedAt) < 150)
        #expect(ended.scrobble == .notEligible)
    }

    @Test("A Play that goes quiet and plays on qualifies once it has played long enough")
    func gapThenQualifies() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)

        world.playFor(140, since: play)
        world.silence(seconds: 3)
        world.recognizer.answers = [.match(.ballad, offset: 150)]
        world.music(seconds: 10)
        await settle()
        world.music(seconds: 10)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").count == 1)
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("A queued Play whose end is dated back before it qualified is never sent")
    func queuedThenEndedEarlier() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 300_000)
        let play = try await world.identify(.ballad)
        world.lastFm.isOffline = true

        // Queued at 150 s, but Last.fm can't be reached.
        world.playFor(155, since: play)
        await settle()
        // A recheck finds the next Track 30 s in: the Play ended at about 125 s.
        world.recognizer.answers = [.match(.rocker, offset: 30)]
        world.music(seconds: 10)
        await settle()
        let triedOffline = world.lastFm.calls.count
        world.lastFm.isOffline = false
        world.pressing.networkBecameAvailable()
        await settle()

        let sentOnline = world.lastFm.calls.dropFirst(triedOffline).filter { $0.method == "track.scrobble" }
        #expect(sentOnline.allSatisfy { $0.scrobbles.allSatisfy { $0.track != Track.ballad.title } })
        let ended = try #require(world.pressing.history.first { $0.id == play.id })
        #expect(try #require(ended.endedAt).timeIntervalSince(ended.startedAt) < 150)
        #expect(ended.scrobble == .notEligible)
        #expect(world.store.scrobbleQueue.isEmpty)
    }

    @Test("Length unknown to Last.fm: the Play qualifies at 4 minutes")
    func unknownLengthAt240() async throws {
        let world = World(lastFm: .listener)
        let play = try await world.identify(.ballad)

        world.playFor(239, since: play)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").isEmpty)

        world.playFor(241, since: play)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").count == 1)
    }

    @Test("Length unknown to Last.fm: a Play that ends after at least 30 s is scrobbled at its end")
    func unknownLengthAtEnd() async throws {
        let world = World(lastFm: .listener)
        let play = try await world.identify(.ballad)

        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").count == 1)
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("Length unknown to Last.fm: a Play that ends before 30 s is not eligible")
    func unknownLengthTooShort() async throws {
        let world = World(lastFm: .listener)
        let play = try await world.identify(.ballad)

        world.playFor(28, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        #expect(world.pressing.history.first?.scrobble == .notEligible)
    }

    @Test("A length of 0 from Last.fm counts as unknown")
    func zeroLength() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.knows(.ballad, durationMilliseconds: 0)
        let play = try await world.identify(.ballad)

        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("A Play that starts while disconnected is never sent, even once Last.fm is connected")
    func madeWhileDisconnected() async throws {
        let world = World()
        let play = try await world.identify(.ballad)

        await world.pressing.connectLastFm()
        world.playFor(300, since: play)
        world.silence(seconds: 15)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").isEmpty)
        #expect(world.lastFm.calls("track.updateNowPlaying").isEmpty)
        #expect(world.pressing.history.first?.scrobble == .notScrobbled)
    }
}

extension World {
    /// The deck plays a Track the recogniser matches; returns its Play.
    @discardableResult
    func identify(_ track: Track) async throws -> Play {
        recognizer.answers = [.match(track, offset: 2)]
        music(seconds: 12)
        await settle()
        return try #require(pressing.state.play)
    }

    /// Lets the Record keep playing, with no new audio and no searches
    /// answered, until the Play has run this long.
    func playFor(_ seconds: TimeInterval, since play: Play) {
        let until = play.startedAt.addingTimeInterval(seconds)
        scheduler.advance(by: max(0, until.timeIntervalSince(scheduler.now)))
    }
}
