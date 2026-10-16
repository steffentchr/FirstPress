import Foundation

/// Identifies what the deck is playing, one bounded search at a time, and
/// turns the answers into Plays.
///
/// A search collects `searchSeconds` of mono audio while a Record is playing,
/// outside its Gaps, then hands it to the Recognizer once, which answers
/// match or no-match. Searches run when a Record starts, after each Gap, and
/// as a recheck 30 s after the last search started.
@MainActor
final class Identifier {
    enum Event {
        /// A new Track matched: a Play starts.
        case playStarted(Play)
        /// The current Play ended, with its end time set.
        case playEnded(Play)
    }

    /// How much audio one search hands the Recognizer. ShazamKit wants a
    /// signature between its catalog's minimum and maximum (about 3 to 12 s).
    static let searchSeconds: TimeInterval = 8
    /// A recheck runs this long after the last search started, so Tracks that
    /// run into each other without a Gap still get picked up.
    static let recheckSeconds: TimeInterval = 30

    private enum Trigger {
        case recordStart
        /// After a Gap whose silence began at this time.
        case gap(silenceBegan: Date)
        case recheck
    }

    private let recognizer: any Recognizer
    private let scheduler: any Scheduler
    private let onEvent: @MainActor (Event) -> Void

    private(set) var play: Play?

    /// The search collecting audio, if any.
    private var collecting: Trigger?
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    private var recheckTimer: (any ScheduledWork)?
    /// The search after a Gap missed while a Play was current: when that
    /// Gap's silence began. One more miss ends the Play as of then.
    private var missedAfterGap: Date?
    /// Bumped whenever the Record ends, so an answer to a search from before
    /// then is ignored.
    private var generation = 0

    init(recognizer: any Recognizer, scheduler: any Scheduler, onEvent: @escaping @MainActor (Event) -> Void) {
        self.recognizer = recognizer
        self.scheduler = scheduler
        self.onEvent = onEvent
    }

    func recordStarted() {
        startSearch(.recordStart)
    }

    /// The search collects once the music comes back.
    func gap(silenceBegan: Date) {
        startSearch(.gap(silenceBegan: silenceBegan))
    }

    /// The Record ended. The current Play ends as of when the silence began.
    func flip(silenceBegan: Date) {
        generation += 1
        collecting = nil
        samples = []
        recheckTimer?.cancel()
        recheckTimer = nil
        missedAfterGap = nil
        endPlay(at: silenceBegan)
    }

    /// Audio from the deck while a Record is playing, outside its Gaps.
    func add(_ buffer: PCMBuffer) {
        guard let trigger = collecting else { return }
        if buffer.sampleRate != sampleRate {
            samples = []
            sampleRate = buffer.sampleRate
        }
        samples += zip(buffer.left, buffer.right).map { ($0 + $1) / 2 }
        guard Double(samples.count) >= Self.searchSeconds * sampleRate else { return }
        let audio = samples, rate = sampleRate, generation = generation
        collecting = nil
        samples = []
        Task { [weak self, recognizer] in
            // A failure (no network, Shazam's servers) is neither a match nor a miss.
            let answer = try? await recognizer.recognize(audio, sampleRate: rate)
            guard let self, generation == self.generation, let answer else { return }
            answered(answer, trigger: trigger)
        }
    }

    private func answered(_ answer: Recognition, trigger: Trigger) {
        switch answer {
        case .match(let track, _):
            missedAfterGap = nil
            if let play, play.track.isSame(as: track) { return }
            endPlay(at: scheduler.now)
            let play = Play(track: track, startedAt: scheduler.now)
            self.play = play
            onEvent(.playStarted(play))
        case .noMatch:
            if let gap = missedAfterGap {
                missedAfterGap = nil
                endPlay(at: gap)
            } else if case .gap(let silenceBegan) = trigger, play != nil {
                missedAfterGap = silenceBegan
            }
        }
    }

    private func endPlay(at time: Date) {
        guard var play else { return }
        self.play = nil
        play.endedAt = max(time, play.startedAt)
        onEvent(.playEnded(play))
    }

    private func startSearch(_ trigger: Trigger) {
        collecting = trigger
        samples = []
        recheckTimer?.cancel()
        recheckTimer = scheduler.schedule(after: Self.recheckSeconds) { [weak self] in
            guard let self, collecting == nil else { return }
            startSearch(.recheck)
        }
    }
}
