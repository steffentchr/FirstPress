import AppKit
import SwiftUI
import FirstPressMenuCore

/// First Press Menu: a menu-bar extra with no Dock icon (`LSUIElement`). Its
/// icon opens a panel that shows what's playing on the First Press found on
/// the network. The gear in the panel opens Settings.
@main
struct FirstPressMenuApp: App {
    @State private var menu: FirstPressMenu
    @State private var settings: MenuSettings
    @State private var loginItem = LoginItem()
    @State private var notifications: UserNotifications

    init() {
        let notifications = UserNotifications()
        let menu = FirstPressMenu(link: BonjourMenuLink(), scheduler: MainQueueScheduler(), notifier: notifications)
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
                .followsAppAppearance()
        } label: {
            MenuBarIcon(menu: menu)
        }
        .menuBarExtraStyle(.window)

        Window("First Press Menu Settings", id: SettingsView.windowID) {
            SettingsView(menu: menu, settings: settings, loginItem: loginItem, notifications: notifications)
                .followsAppAppearance()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

extension SettingsView {
    static let windowID = "settings"
}

/// An icon only, no text: a template image of a stylised record, a
/// one-line circle around a solid label. One thin groove ring appears while
/// a Record plays. While no phone is connected it's the idle icon dimmed,
/// as macOS dims a disabled menu-bar item, not a different drawing.
struct MenuBarIcon: View {
    let menu: FirstPressMenu

    var body: some View {
        icon.accessibilityLabel("First Press Menu")
    }

    private var icon: Image {
        switch menu.connection {
        case .connected: Image(menu.isRecordPlaying ? "MenuBarIconPlaying" : "MenuBarIcon")
        case .looking, .cantBeReached, .needsUpdate: Image(nsImage: Self.dimmed)
        }
    }

    /// The idle icon at reduced opacity, still a template image so macOS
    /// tints it for a light or dark menu bar.
    private static let dimmed: NSImage = {
        guard let source = NSImage(named: "MenuBarIcon") else { return NSImage() }
        let image = NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
