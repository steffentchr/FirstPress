import Foundation

/// Turns the level into Record and Session events.
///
/// Every duration is measured with the Scheduler: the level only says whether
/// the deck is above or below the threshold right now, and timers decide when
/// that has lasted long enough.
@MainActor
final class Detector {
    enum Event {
        /// The level stayed above the threshold for the start delay.
        case recordStarted
        /// Within a Record, the level stayed below the threshold for a Gap.
        case gap
        /// Music came back after a Gap, before a Flip.
        case resumed
        /// The level stayed below the threshold for the Flip threshold. The Record has ended.
        case flip
        /// The silence that caused the Flip reached the stop delay, counted
        /// from when it began, with no Record starting.
        case sessionEnded
    }

    /// How long a silence within a Record lasts before it counts as a Gap.
    static let gapSeconds: TimeInterval = 1.5

    var settings = DetectionSettings()

    private let scheduler: any Scheduler
    private let onEvent: @MainActor (Event) -> Void

    private var isAbove = false
    private var inRecord = false
    private var inGap = false
    private var timers: [any ScheduledWork] = []
    /// Runs from a Flip until a new Record starts, independent of the level,
    /// and fires the stop delay after the silence began.
    private var sessionTimer: (any ScheduledWork)?

    init(scheduler: any Scheduler, onEvent: @escaping @MainActor (Event) -> Void) {
        self.scheduler = scheduler
        self.onEvent = onEvent
    }

    /// The current level in dBFS.
    func level(_ dBFS: Double) {
        let above = dBFS >= settings.threshold
        guard above != isAbove else { return }
        isAbove = above
        cancelTimers()
        if above {
            if inRecord {
                if inGap {
                    inGap = false
                    onEvent(.resumed)
                }
            } else {
                after(settings.startDelay) { $0.startRecord() }
            }
        } else if inRecord {
            after(Self.gapSeconds) { $0.enterGap() }
            after(settings.flipThreshold) { $0.flip() }
        }
    }

    private func startRecord() {
        sessionTimer?.cancel()
        sessionTimer = nil
        inRecord = true
        inGap = false
        onEvent(.recordStarted)
    }

    private func enterGap() {
        inGap = true
        onEvent(.gap)
    }

    private func flip() {
        inRecord = false
        inGap = false
        onEvent(.flip)
        // The Flip comes the Flip threshold into the silence.
        sessionTimer = scheduler.schedule(after: settings.stopDelay - settings.flipThreshold) { [weak self] in
            guard let self else { return }
            sessionTimer = nil
            onEvent(.sessionEnded)
        }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor (Detector) -> Void) {
        timers.append(scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            work(self)
        })
    }

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers = []
    }
}
