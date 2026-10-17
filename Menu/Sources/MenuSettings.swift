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

    /// Notifications for new Tracks and Flips. On by default.
    var notificationsAreOn: Bool {
        didSet {
            defaults.set(notificationsAreOn, forKey: Keys.notificationsAreOn)
            menu.notificationsAreOn = notificationsAreOn
        }
    }

    var findTracksIn: TrackSearchService {
        didSet { defaults.set(findTracksIn.rawValue, forKey: Keys.findTracksIn) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let menu: PressingMenu

    private enum Keys {
        static let appearance = "appearance"
        // Stored under its first name, so the choice survives the rename.
        static let notificationsAreOn = "notifiesOnNewTrack"
        // Stored under its first name, so the choice survives the rename.
        static let findTracksIn = "findSongsIn"
    }

    init(menu: PressingMenu, defaults: UserDefaults = .standard) {
        self.menu = menu
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? .system
        notificationsAreOn = defaults.object(forKey: Keys.notificationsAreOn) as? Bool ?? true
        findTracksIn = defaults.string(forKey: Keys.findTracksIn).flatMap(TrackSearchService.init) ?? .default
        menu.notificationsAreOn = notificationsAreOn
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
