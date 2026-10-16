import Foundation
import Testing
import PressingCore

/// The durable queue: batches of up to 50, retries, and what Last.fm refuses.
@MainActor
@Suite("Scrobble queue")
struct ScrobbleQueueTests {
    @Test("A batch is signed like any call: the known track.scrobble vector")
    func batchSignature() async throws {
        let kraftwerk = Play(
            track: Track(artist: "Kraftwerk", title: "Autobahn", album: "Autobahn"),
            startedAt: Date(timeIntervalSince1970: 1_760_000_000),
            endedAt: Date(timeIntervalSince1970: 1_760_001_000),
            scrobble: .pending
        )
        // Decomposed accents, as a recogniser might return them, are signed
        // and sent precomposed.
        let sigurRos = Play(
            track: Track(artist: "Sigur Ro\u{301}s", title: "Hoppi\u{301}polla"),
            startedAt: Date(timeIntervalSince1970: 1_760_001_000),
            endedAt: Date(timeIntervalSince1970: 1_760_001_400),
            scrobble: .pending
        )
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [sigurRos, kraftwerk], scrobbleQueue: [sigurRos.id, kraftwerk.id])

        let world = World(
            store: store,
            account: LastFmAccount(apiKey: "0123456789abcdef0123456789abcdef", secret: "s3cr3t"),
            lastFm: LastFmSession(username: "listener", key: "SESSIONKEY123")
        )
        await settle()

        let batch = try #require(world.lastFm.calls("track.scrobble").first)
        #expect(batch.params["api_sig"] == "2fedf2f6e8174df049bbd15d692a66d8")
        #expect(batch.params["artist[1]"] == "Sigur Rós")
        #expect(batch.params["album[1]"] == nil)
        #expect(batch.encoded.contains("Sigur%20R%C3%B3s"))
        #expect(world.store.plays.allSatisfy { $0.scrobble == .scrobbled })
        #expect(world.store.scrobbleQueue.isEmpty)
    }

    @Test("A title with + & = survives the form encoding")
    func formEncoding() async throws {
        let play = Play(track: Track(artist: "Simon & Garfunkel", title: "1+1=2"), startedAt: Date(timeIntervalSince1970: 1_760_000_000), endedAt: Date(timeIntervalSince1970: 1_760_000_100), scrobble: .pending)
        let world = World(store: FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [play], scrobbleQueue: [play.id]), lastFm: .listener)
        await settle()

        let batch = try #require(world.lastFm.calls("track.scrobble").first)
        #expect(batch.params["artist[0]"] == "Simon & Garfunkel")
        #expect(batch.params["track[0]"] == "1+1=2")
        #expect(batch.encoded.contains("1%2B1%3D2"))
    }

    @Test("Plays owed are sent in batches of up to 50, oldest first")
    func batchesOf50() async throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let plays = (0..<120).map { index in
            Play(track: Track(artist: "Artist \(index)", title: "Title \(index)"), startedAt: start.addingTimeInterval(Double(index) * 300), endedAt: start.addingTimeInterval(Double(index) * 300 + 250), scrobble: .pending)
        }
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: plays.reversed(), scrobbleQueue: plays.shuffled().map(\.id))

        let world = World(store: store, lastFm: .listener)
        await settle()

        let batches = world.lastFm.calls("track.scrobble")
        #expect(batches.map(\.scrobbles.count) == [50, 50, 20])
        #expect(batches.flatMap(\.scrobbles).map(\.artist) == plays.map(\.track.artist))
        #expect(world.store.plays.allSatisfy { $0.scrobble == .scrobbled })
    }

    @Test("The queue survives a restart")
    func surviveRestart() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.isOffline = true
        let play = try await world.identify(.ballad)
        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()
        #expect(world.pressing.history.first?.scrobble == .pending)
        #expect(world.store.scrobbleQueue == [play.id])

        let restarted = World(store: world.store, keychain: world.keychain)
        await settle()

        let batch = try #require(restarted.lastFm.calls("track.scrobble").first)
        #expect(batch.scrobbles.first?.track == "Wuthering Heights")
        #expect(restarted.pressing.history.first?.scrobble == .scrobbled)
        #expect(restarted.store.scrobbleQueue.isEmpty)
    }

    @Test("A Play cut short by the app stopping, before it qualified, is not eligible after a restart")
    func cutShortByRestart() async throws {
        let world = World(lastFm: .listener)
        let play = try await world.identify(.ballad)
        #expect(world.store.plays.first?.scrobble == .pending)

        let restarted = World(store: world.store, keychain: world.keychain)
        await settle()

        #expect(restarted.pressing.history.first { $0.id == play.id }?.scrobble == .notEligible)
        #expect(restarted.lastFm.calls("track.scrobble").isEmpty)
    }

    @Test("No network: the Play stays pending and is retried with backoff")
    func retryWithBackoff() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.isOffline = true
        let play = try await world.identify(.ballad)
        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()
        let tries = world.lastFm.calls("track.scrobble").count
        #expect(tries == 1)
        #expect(world.pressing.history.first?.scrobble == .pending)

        world.scheduler.advance(by: 10 * 60)
        await settle()
        let retries = world.lastFm.calls("track.scrobble").count
        #expect(retries > 1)
        // Backoff: far fewer tries than one every few seconds.
        #expect(retries < 10)

        world.lastFm.isOffline = false
        world.scheduler.advance(by: 30 * 60)
        await settle()
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
        let sent = world.lastFm.calls("track.scrobble").count
        world.scheduler.advance(by: 60 * 60)
        await settle()
        #expect(world.lastFm.calls("track.scrobble").count == sent)
    }

    @Test("When connectivity returns, Plays owed are sent at once")
    func connectivityReturns() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.isOffline = true
        let play = try await world.identify(.ballad)
        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()

        world.lastFm.isOffline = false
        world.pressing.networkBecameAvailable()
        await settle()

        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("Last.fm offline or busy (11, 16): pending, and tried again")
    func serviceOffline() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.answers["track.scrobble"] = { _ in .lastFmError(11, "Service Offline", status: 503) }
        let play = try await world.identify(.ballad)
        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()
        #expect(world.pressing.history.first?.scrobble == .pending)

        world.lastFm.answers["track.scrobble"] = FakeLastFm.acceptingEveryPlay
        world.scheduler.advance(by: 60 * 60)
        await settle()
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("Last.fm ignoring one Play in a batch makes that Play rejected, and the others scrobbled")
    func ignoredPerItem() async throws {
        let first = Play(track: .ballad, startedAt: Date(timeIntervalSince1970: 1_760_000_000), endedAt: Date(timeIntervalSince1970: 1_760_000_200), scrobble: .pending)
        let second = Play(track: .rocker, startedAt: Date(timeIntervalSince1970: 1_760_000_200), endedAt: Date(timeIntervalSince1970: 1_760_000_400), scrobble: .pending)
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [first, second], scrobbleQueue: [first.id, second.id])
        let world = World(store: store, lastFm: .listener, answering: ["track.scrobble": { _ in .scrobbles(ignoredCodes: [3, 0]) }])
        await settle()

        #expect(world.pressing.history.first { $0.id == first.id }?.scrobble == .rejected)
        #expect(world.pressing.history.first { $0.id == second.id }?.scrobble == .scrobbled)
        #expect(world.store.scrobbleQueue.isEmpty)
    }

    @Test("A batch Last.fm refuses as malformed is rejected and not retried")
    func refusedBatch() async throws {
        let play = Play(track: .ballad, startedAt: Date(timeIntervalSince1970: 1_760_000_000), endedAt: Date(timeIntervalSince1970: 1_760_000_200), scrobble: .pending)
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [play], scrobbleQueue: [play.id])
        let world = World(store: store, lastFm: .listener, answering: ["track.scrobble": { _ in .lastFmError(6, "Invalid parameters") }])
        await settle()
        world.scheduler.advance(by: 60 * 60)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").count == 1)
        #expect(world.pressing.history.first?.scrobble == .rejected)
    }

    @Test("A revoked session: Last.fm shows disconnected, and Plays owed wait until it is connected again")
    func sessionRevoked() async throws {
        let play = Play(track: .ballad, startedAt: Date(timeIntervalSince1970: 1_760_000_000), endedAt: Date(timeIntervalSince1970: 1_760_000_200), scrobble: .pending)
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [play], scrobbleQueue: [play.id])
        let world = World(store: store, lastFm: .listener, answering: ["track.scrobble": { _ in .lastFmError(9, "Invalid session key - Please re-authenticate", status: 403) }])
        await settle()

        #expect(world.pressing.state.lastFm == LastFmState(connection: .disconnected, problem: .sessionRevoked))
        #expect(world.keychain.session == nil)
        #expect(world.pressing.history.first?.scrobble == .pending)

        world.lastFm.answers["track.scrobble"] = FakeLastFm.acceptingEveryPlay
        await world.pressing.connectLastFm()
        await settle()
        #expect(world.pressing.history.first?.scrobble == .scrobbled)
    }

    @Test("Pressing's API key refused: the problem shows, and Plays owed stay pending")
    func misconfigured() async throws {
        let play = Play(track: .ballad, startedAt: Date(timeIntervalSince1970: 1_760_000_000), endedAt: Date(timeIntervalSince1970: 1_760_000_200), scrobble: .pending)
        let store = FakeStore(settings: Settings(inputID: AudioInputDevice.deck.id), plays: [play], scrobbleQueue: [play.id])
        let world = World(store: store, lastFm: .listener, answering: ["track.scrobble": { _ in .lastFmError(10, "Invalid API key") }])
        await settle()

        #expect(world.pressing.state.lastFm.problem == .misconfigured(code: 10))
        #expect(world.pressing.history.first?.scrobble == .pending)
    }

    @Test("Disconnecting: Plays still owed are not scrobbled, and never sent")
    func disconnectDropsQueue() async throws {
        let world = World(lastFm: .listener)
        world.lastFm.isOffline = true
        let play = try await world.identify(.ballad)
        world.playFor(31, since: play)
        world.silence(seconds: 15)
        await settle()

        world.pressing.disconnectLastFm()
        world.lastFm.isOffline = false
        await world.pressing.connectLastFm()
        world.pressing.networkBecameAvailable()
        world.scheduler.advance(by: 60 * 60)
        await settle()

        #expect(world.lastFm.calls("track.scrobble").count == 1)
        #expect(world.pressing.history.first?.scrobble == .notScrobbled)
        #expect(world.store.scrobbleQueue.isEmpty)
    }
}
