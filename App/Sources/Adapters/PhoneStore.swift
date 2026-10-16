import Foundation
import os
import PressingCore

/// Production Store. Settings are one small JSON value in UserDefaults; Plays
/// go in a SQLite database (`PlayDatabase`), since History is kept
/// indefinitely and each Play is saved several times as it changes.
/// Credentials never go here.
@MainActor
final class PhoneStore: Store {
    private let defaults: UserDefaults
    private let settingsKey = "settings"
    private let plays: PlayDatabase?
    private let log = Logger(subsystem: "Pressing", category: "Store")

    init(defaults: UserDefaults = .standard, directory: URL = PhoneStore.defaultDirectory) {
        self.defaults = defaults
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = try PlayDatabase(url: directory.appending(path: "history.sqlite"))
            plays = database
            Self.migrateLegacyPlays(from: defaults, to: database)
        } catch {
            log.error("History can't be opened: \(error)")
            plays = nil
        }
    }

    /// Application Support, not Caches: iOS may empty Caches, and History is
    /// kept indefinitely.
    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Pressing", directoryHint: .isDirectory)
    }

    func loadSettings() -> Settings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    func saveSettings(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    func savePlay(_ play: Play) {
        do {
            try plays?.save(play)
        } catch {
            log.error("A Play can't be saved: \(error)")
        }
    }

    func loadPlays() -> [Play] {
        do {
            return try plays?.all() ?? []
        } catch {
            log.error("History can't be read: \(error)")
            return []
        }
    }

    /// Before History, ended Plays went to a JSON list in UserDefaults. Move
    /// them into the database once, then drop the list.
    private static func migrateLegacyPlays(from defaults: UserDefaults, to database: PlayDatabase) {
        let key = "plays"
        guard let data = defaults.data(forKey: key) else { return }
        let legacy = (try? JSONDecoder().decode([Play].self, from: data)) ?? []
        do {
            for play in legacy { try database.save(play) }
            defaults.removeObject(forKey: key)
        } catch {
            // Leave the list in place; the next launch tries again.
        }
    }
}
