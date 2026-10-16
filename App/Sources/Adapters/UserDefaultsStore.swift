import Foundation
import PressingCore

/// Production Store: settings as JSON in UserDefaults. Credentials never go here.
@MainActor
final class UserDefaultsStore: Store {
    private let defaults: UserDefaults
    private let settingsKey = "settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> Settings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    func saveSettings(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}
