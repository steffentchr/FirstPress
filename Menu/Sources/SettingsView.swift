import AppKit
import SwiftUI
import PressingMenuCore

/// The Settings window, in the reference layout: grouped rows, each with a
/// title and a one-line explanation on the left and its control on the
/// right, then an About footer.
struct SettingsView: View {
    let menu: PressingMenu
    @Bindable var settings: MenuSettings
    let loginItem: LoginItem
    let notifications: UserNotifications

    static let projectURL = URL(string: "https://github.com/steffentchr/Pressing")!
    /// The same policy the App Store listing links to (AppStore/Metadata).
    static let privacyURL = URL(string: "https://github.com/steffentchr/Pressing/blob/main/AppStore/privacy-policy.md")!

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingsRow("Appearance", detail: "Light, dark, or follow macOS.") {
                        Picker("Appearance", selection: $settings.appearance) {
                            Image(systemName: "circle.lefthalf.filled")
                                .help("System")
                                .accessibilityLabel("System")
                                .tag(MenuSettings.Appearance.system)
                            Image(systemName: "sun.max")
                                .help("Light")
                                .accessibilityLabel("Light")
                                .tag(MenuSettings.Appearance.light)
                            Image(systemName: "moon")
                                .help("Dark")
                                .accessibilityLabel("Dark")
                                .tag(MenuSettings.Appearance.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow("Launch at login", detail: loginItem.needsApproval ? nil : "Open Pressing Menu when you log in.") {
                        Toggle("Launch at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    } link: {
                        if loginItem.needsApproval {
                            Button("Allow in System Settings") { loginItem.openSystemSettings() }
                                .buttonStyle(.link)
                        }
                    }
                    // Shown as the model decides: off while macOS denies them.
                    SettingsRow("Notify on new Track", detail: menu.notificationsAreDenied ? nil : "A notification for each new Track identified.") {
                        Toggle("Notify on new Track", isOn: Binding(
                            get: { menu.postsNotifications },
                            set: { settings.notifiesOnNewTrack = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(menu.notificationsAreDenied)
                    } link: {
                        if menu.notificationsAreDenied {
                            Link("Allow in System Settings", destination: notifications.systemSettingsURL)
                        }
                    }
                    SettingsRow("Find songs in", detail: "Click the song in the panel.") {
                        Picker("Find songs in", selection: $settings.findTracksIn) {
                            Text("Spotify").tag(TrackSearchService.spotify)
                            Text("Apple Music").tag(TrackSearchService.appleMusic)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            AboutFooter()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    /// The listener can change both in System Settings while this is open.
    private func refresh() async {
        loginItem.refresh()
        await notifications.refresh()
    }
}

/// A title and a one-line explanation on the left, the control on the right.
private struct SettingsRow<Control: View, Extra: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control
    @ViewBuilder let link: Extra

    init(_ title: String, detail: String?, @ViewBuilder control: () -> Control, @ViewBuilder link: () -> Extra = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.control = control()
        self.link = link()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                link
                    .font(.callout)
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, 2)
    }
}

/// The app icon, name, version and build, and links to the project and the
/// privacy policy.
private struct AboutFooter: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pressing Menu")
                    .font(.headline)
                Text("Version \(Self.version) (\(Self.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link("Project", destination: SettingsView.projectURL)
            Link("Privacy", destination: SettingsView.privacyURL)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
