import SwiftUI
import PressingMenuCore

/// Pressing Menu: a menu-bar extra with no Dock icon (`LSUIElement`). Its
/// icon opens a panel that shows what's playing on the Pressing found on
/// the network.
@main
struct PressingMenuApp: App {
    @State private var menu: PressingMenu

    init() {
        let menu = PressingMenu(link: BonjourMenuLink(), scheduler: MainQueueScheduler())
        menu.start()
        _menu = State(initialValue: menu)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(menu: menu)
        } label: {
            MenuBarIcon(menu: menu)
        }
        .menuBarExtraStyle(.window)
    }
}

/// An icon only, no text. It looks different while the iPhone can't be
/// reached, and fills in while a Record plays.
struct MenuBarIcon: View {
    let menu: PressingMenu

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("Pressing Menu")
    }

    private var symbol: String {
        switch menu.connection {
        case .connected: menu.isRecordPlaying ? "record.circle.fill" : "record.circle"
        case .looking, .cantBeReached, .needsUpdate: "circle.dashed"
        }
    }
}
