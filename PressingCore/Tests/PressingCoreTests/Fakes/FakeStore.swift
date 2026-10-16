import Foundation
import PressingCore

/// In-memory Store. Share one between two cores to simulate a restart.
@MainActor
final class FakeStore: Store {
    var settings: Settings?

    init(settings: Settings? = nil) {
        self.settings = settings
    }

    func loadSettings() -> Settings? { settings }
    func saveSettings(_ settings: Settings) { self.settings = settings }

    /// Ended Plays, in the order they were saved.
    private(set) var plays: [Play] = []
    func savePlay(_ play: Play) { plays.append(play) }
    /// Plays that have ended, in the order they were saved.
    var endedPlays: [Play] { plays.filter { $0.endedAt != nil } }
}
