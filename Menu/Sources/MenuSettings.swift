import AppKit
import Observation
import PressingMenuCore

/// Pressing Menu's Settings, kept in the Mac's user defaults so they're
/// remembered between launches. Launch at login isn't here: the system's
/// login-item service remembers that itself (`LoginItem`).
@MainActor
@Observable
final class MenuSettings {
    enum Appearance: String, CaseIterable {
        /// Follows macOS.
        case system
        case light
        case dark
    }

    var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    /// On by default.
    var notifiesOnNewTrack: Bool {
        didSet {
            defaults.set(notifiesOnNewTrack, forKey: Keys.notifiesOnNewTrack)
            menu.notifiesOnNewTrack = notifiesOnNewTrack
        }
    }

    var findSongsIn: SongService {
        didSet { defaults.set(findSongsIn.rawValue, forKey: Keys.findSongsIn) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let menu: PressingMenu

    private enum Keys {
        static let appearance = "appearance"
        static let notifiesOnNewTrack = "notifiesOnNewTrack"
        static let findSongsIn = "findSongsIn"
    }

    init(menu: PressingMenu, defaults: UserDefaults = .standard) {
        self.menu = menu
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? .system
        notifiesOnNewTrack = defaults.object(forKey: Keys.notifiesOnNewTrack) as? Bool ?? true
        findSongsIn = defaults.string(forKey: Keys.findSongsIn).flatMap(SongService.init) ?? .default
        menu.notifiesOnNewTrack = notifiesOnNewTrack
        applyAppearance()
    }

    /// Re-themes the panel and the Settings window at once: both follow the
    /// app's appearance.
    private func applyAppearance() {
        NSApplication.shared.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
