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
}
