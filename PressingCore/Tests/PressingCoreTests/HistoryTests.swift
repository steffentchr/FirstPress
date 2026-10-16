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

    @Test("History has a header per day in the listener's time zone, newest day first")
    func dayHeaders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Copenhagen"))
        let formatter = ISO8601DateFormatter()
        func play(_ track: Track, at time: String) throws -> Play {
            Play(track: track, startedAt: try #require(formatter.date(from: time)))
        }
        // 22:30 UTC on the 16th is half past midnight on the 17th in Copenhagen.
        let saturdayLate = try play(.rocker, at: "2026-10-17T09:00:00Z")
        let saturdayEarly = try play(.ballad, at: "2026-10-16T22:30:00Z")
        let friday = try play(.ballad, at: "2026-10-16T08:00:00Z")

        let days = HistoryDay.days(of: [saturdayLate, saturdayEarly, friday], calendar: calendar)

        #expect(days.map(\.plays) == [[saturdayLate, saturdayEarly], [friday]])
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)))
        let fridayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        #expect(days.map(\.day) == [saturday, fridayStart])
    }
}
