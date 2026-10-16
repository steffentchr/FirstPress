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
    /// When the current Record started: no Play in it starts earlier.
    private var recordStart: Date?
    /// When the last Play ended: the next one starts no earlier.
    private var previousEnd: Date?

    /// The search collecting audio, if any.
    private var collecting: Trigger?
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    /// When the audio collected for the search began.
    private var samplesStart: Date?
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

    /// A Record started; its music began at `at`.
    func recordStarted(at start: Date) {
        recordStart = start
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
        if samples.isEmpty {
            // A buffer arrives once its audio has been captured.
            samplesStart = scheduler.now.addingTimeInterval(-Double(buffer.frameCount) / buffer.sampleRate)
        }
        samples += zip(buffer.left, buffer.right).map { ($0 + $1) / 2 }
        guard Double(samples.count) >= Self.searchSeconds * sampleRate else { return }
        let audio = samples, rate = sampleRate, generation = generation
        let audioStart = samplesStart ?? scheduler.now
        collecting = nil
        samples = []
        Task { [weak self, recognizer] in
            // A failure (no network, Shazam's servers) is neither a match nor a miss.
            let answer = try? await recognizer.recognize(audio, sampleRate: rate)
            guard let self, generation == self.generation, let answer else { return }
            answered(answer, trigger: trigger, audioStart: audioStart)
        }
    }

    private func answered(_ answer: Recognition, trigger: Trigger, audioStart: Date) {
        switch answer {
        case .match(let track, let offset):
            missedAfterGap = nil
            if let play, play.track.isSame(as: track) { return }
            // The latest of: worked back from the match, the Record start,
            // and the end of the previous Play.
            var start = max(audioStart.addingTimeInterval(-offset), recordStart ?? .distantPast, previousEnd ?? .distantPast)
            if let current = play {
                // The current Play gives way to this one: at the Gap the search
                // followed, or else where this one starts.
                if case .gap(let silenceBegan) = trigger {
                    start = max(start, silenceBegan)
                }
                start = max(start, current.startedAt)
                endPlay(at: start)
            }
            let play = Play(track: track, startedAt: start)
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
        previousEnd = play.endedAt
        onEvent(.playEnded(play))
    }

    private func startSearch(_ trigger: Trigger) {
        collecting = trigger
        samples = []
        scheduleRecheck()
    }

    /// A search still collecting (after a long Gap, say) puts the recheck
    /// off another 30 s rather than cancelling it.
    private func scheduleRecheck() {
        recheckTimer?.cancel()
        recheckTimer = scheduler.schedule(after: Self.recheckSeconds) { [weak self] in
            guard let self else { return }
            if collecting == nil {
                startSearch(.recheck)
            } else {
                scheduleRecheck()
            }
        }
    }
}
