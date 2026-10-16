import Foundation

/// A timer that can be cancelled before it fires.
@MainActor
public protocol ScheduledWork: AnyObject {
    func cancel()
}

/// Port: the Clock / Scheduler. Time and timers, so every delay, poll and
/// recheck is deterministic in tests. (Named `Scheduler` rather than `Clock`
/// to stay clear of the standard library's `Clock` protocol.)
@MainActor
public protocol Scheduler: AnyObject {
    /// Wall-clock time now.
    var now: Date { get }

    /// Runs `work` on the main actor after `delay` seconds.
    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork
}
