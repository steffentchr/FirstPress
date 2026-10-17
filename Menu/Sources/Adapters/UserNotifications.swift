import AppKit
import Observation
@preconcurrency import UserNotifications
import PressingCore
import PressingMenuCore

/// Production TrackNotifier: posts a Mac notification for each new Track
/// Pressing Menu's model picks. The title is the heading, the artist (and
/// the album, if known by then) below, with the cover attached once its
/// artwork loads. Clicking it opens the panel.
@MainActor
@Observable
final class UserNotifications: NSObject, TrackNotifier {
    /// The listener turned notifications off for Pressing Menu in System
    /// Settings: Settings shows the switch off, with a link there.
    private(set) var isDenied = false
    /// Opens the panel: called when the listener clicks a notification.
    @ObservationIgnored var onOpen: (() -> Void)?

    /// How long a cover may take to load before the notification goes
    /// without it.
    private nonisolated static let artworkTimeout: TimeInterval = 4

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

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
        isDenied = await center.notificationSettings().authorizationStatus == .denied
    }

    /// System Settings › Notifications, at Pressing Menu.
    var systemSettingsURL: URL {
        let id = Bundle.main.bundleIdentifier ?? ""
        return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!
    }

    func notify(newTrack track: Track) {
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        content.threadIdentifier = "tracks"
        Task {
            if let url = track.artworkURL, let cover = await Self.loadCover(url) {
                content.attachments = [cover]
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
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
