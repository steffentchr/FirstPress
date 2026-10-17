import AppKit
import SwiftUI
import PressingMenuCore

/// Pressing Menu: a menu-bar extra with no Dock icon (`LSUIElement`). Its
/// icon opens a panel that shows what's playing on the Pressing found on
/// the network. The gear in the panel opens Settings.
@main
struct PressingMenuApp: App {
    @State private var menu: PressingMenu
    @State private var settings: MenuSettings
    @State private var loginItem = LoginItem()
    @State private var notifications: UserNotifications

    init() {
        let notifications = UserNotifications()
        let menu = PressingMenu(link: BonjourMenuLink(), scheduler: MainQueueScheduler(), notifier: notifications)
        let settings = MenuSettings(menu: menu)
        notifications.onOpen = { PanelWindow.open() }
        notifications.onDeniedChange = { menu.notificationsAreDenied = $0 }
        // Asked at first launch; macOS only shows the prompt once.
        notifications.requestPermission()
        menu.start()
        _menu = State(initialValue: menu)
        _settings = State(initialValue: settings)
        _notifications = State(initialValue: notifications)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(menu: menu)
                .environment(settings)
        } label: {
            MenuBarIcon(menu: menu)
        }
        .menuBarExtraStyle(.window)

        Window("Pressing Menu Settings", id: SettingsView.windowID) {
            SettingsView(menu: menu, settings: settings, loginItem: loginItem, notifications: notifications)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

extension SettingsView {
    static let windowID = "settings"
}

/// An icon only, no text: a template image of the app icon's record and
/// brush. It's dashed while the iPhone can't be reached, and fills in while
/// a Record plays.
struct MenuBarIcon: View {
    let menu: PressingMenu

    var body: some View {
        Image(imageName)
            .accessibilityLabel("Pressing Menu")
    }

    private var imageName: String {
        switch menu.connection {
        case .connected: menu.isRecordPlaying ? "MenuBarIconPlaying" : "MenuBarIcon"
        case .looking, .cantBeReached, .needsUpdate: "MenuBarIconUnreachable"
        }
    }
}
