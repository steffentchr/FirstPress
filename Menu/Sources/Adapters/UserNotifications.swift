import AppKit
@preconcurrency import UserNotifications
import FirstPressCore
import FirstPressMenuCore

/// Production MenuNotifier: posts the Mac notifications First Press Menu's
/// model picks. Clicking one opens the panel.
///
/// - A new Track: the title as the heading, the artist (and the album, if
///   known by then) below, with the cover attached once its artwork loads.
///   Each replaces the one before and clears itself after `trackLifetime`,
///   so they don't pile up on screen.
/// - A Flip: "Flip the record", with the Record's last Track below. It stays
///   until the listener dismisses it or the model removes it. First Press Menu
///   asks for the Alerts style (`NSUserNotificationAlertStyle` in its
///   Info.plist) so it stays on screen.
///
/// Whether macOS allows notifications is read here and handed to the model
/// through `onDeniedChange`; the model decides whether to post at all.
@MainActor
final class UserNotifications: NSObject, MenuNotifier {
    /// Opens the panel: called when the listener clicks a notification.
    var onOpen: (() -> Void)?
    /// Called with whether the listener turned notifications off for
    /// First Press Menu in System Settings, each time it's read.
    var onDeniedChange: ((Bool) -> Void)?

    /// How long a cover may take to load before the notification goes
    /// without it.
    private nonisolated static let artworkTimeout: TimeInterval = 4
    /// How long a new Track's notification stays before it clears itself.
    private static let trackLifetime: Duration = .seconds(8)
    /// One identifier each: a new Track's notification replaces the last
    /// one, and the Flip's can be removed by name.
    private static let trackID = "track"
    private static let flipID = "flip"

    /// Counts new-Track notifications, so a late cover or a self-clear
    /// leaves a newer Track's notification alone.
    private var trackGeneration = 0

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks for permission. Called at launch; macOS only asks the listener
    /// the first time.
    func requestPermission() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert])
            await refresh()
        }
    }

    /// Reads back whether notifications are allowed, which the listener can
    /// change in System Settings at any time.
    func refresh() async {
        onDeniedChange?(await center.notificationSettings().authorizationStatus == .denied)
    }

    /// System Settings › Notifications, at First Press Menu.
    var systemSettingsURL: URL {
        let id = Bundle.main.bundleIdentifier ?? ""
        return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!
    }

    func notify(newTrack track: Track) {
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        content.threadIdentifier = "tracks"
        trackGeneration += 1
        let generation = trackGeneration
        Task {
            if let url = track.artworkURL, let cover = await Self.loadCover(url) {
                content.attachments = [cover]
            }
            guard generation == trackGeneration else { return }
            let request = UNNotificationRequest(identifier: Self.trackID, content: content, trigger: nil)
            try? await center.add(request)
            try? await Task.sleep(for: Self.trackLifetime)
            guard generation == trackGeneration else { return }
            center.removeDeliveredNotifications(withIdentifiers: [Self.trackID])
        }
    }

    func notifyFlip(lastTrack: Track?) {
        let content = UNMutableNotificationContent()
        content.title = "Flip the record"
        content.body = if let lastTrack {
            "Side over after \(lastTrack.title) by \(lastTrack.artist)."
        } else {
            "The side has run out."
        }
        content.threadIdentifier = "flip"
        let request = UNNotificationRequest(identifier: Self.flipID, content: content, trigger: nil)
        Task { try? await center.add(request) }
    }

    func removeFlip() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.flipID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.flipID])
    }

    /// Downloads the cover into a file the notification can attach.
    private nonisolated static func loadCover(_ url: URL) async -> UNNotificationAttachment? {
        var request = URLRequest(url: url)
        request.timeoutInterval = artworkTimeout
        guard let (downloaded, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        guard (try? FileManager.default.moveItem(at: downloaded, to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "cover", url: file)
    }
}

extension UserNotifications: UNUserNotificationCenterDelegate {
    /// A menu-bar app counts as in front while its panel is open, and the
    /// model already holds notifications back then, so show each one.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }
}
