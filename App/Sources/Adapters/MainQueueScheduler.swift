import Foundation
import PressingCore

/// Production Scheduler: wall-clock time and main-queue timers.
@MainActor
final class MainQueueScheduler: Scheduler {
    private final class Work: ScheduledWork {
        let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    var now: Date { Date() }

    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { work() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return Work(item: item)
    }
}
