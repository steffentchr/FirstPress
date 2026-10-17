import SwiftUI
import PressingCore

/// The app's root: the page the core names (choose input, waiting or Now
/// Playing) under a gear and a speaker icon. History is listed on Now
/// Playing, under the current Track.
///
/// The sheets hang off this view rather than off each page, so an open
/// Settings or Rooms sheet stays open when a Record starts or a Session ends
/// underneath it.
struct RootView: View {
    let pressing: Pressing
    let audioInput: AVAudioSessionInput
    @State private var showingSettings = false
    @State private var showingRooms = false
    @State private var windowAppearance = WindowAppearance()

    private var page: Page { pressing.state.page }

    /// White over the start screen's orange; the primary colour on Now Playing.
    private var iconColor: Color { page == .nowPlaying ? .primary : .white }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .chooseInput(let reason):
                    WaitingView(pressing: pressing, audioInput: audioInput, chooseInput: reason)
                case .waiting:
                    WaitingView(pressing: pressing, audioInput: audioInput, chooseInput: nil)
                case .nowPlaying:
                    NowPlayingView(pressing: pressing, play: pressing.state.play)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.4), value: page)
            // The two icons are Pressing's own row rather than toolbar items:
            // the system's bar buttons ignore a fade, and kiosk mode fades them.
            // The row always keeps its height, so nothing moves when they fade.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    // Before any input is chosen, no Rooms are looked for yet.
                    if page != .chooseInput(.noneChosen) {
                        iconButton("Rooms", systemImage: "hifispeaker.2") { showingRooms = true }
                    }
                    iconButton("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                .font(.title2)
                .buttonStyle(.plain)
                .foregroundStyle(iconColor)
                .frame(height: 44)
                .padding(.horizontal, 8)
                .kioskHidden(hidesControls)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(pressing: pressing)
                    .screenBlanker(pressing)
                    .preferredColorScheme(sheetColorScheme)
            }
            .sheet(isPresented: $showingRooms) {
                RoomsSheet(pressing: pressing)
                    .screenBlanker(pressing)
                    .preferredColorScheme(sheetColorScheme)
            }
            .background { WindowReader { windowAppearance.attach($0) } }
        }
        .screenBlanker(pressing)
        // Kiosk mode: no clock, battery or other status bar, and the home
        // indicator fades away until the screen is touched near it.
        .statusBarHidden(isKiosk)
        .persistentSystemOverlays(isKiosk ? .hidden : .automatic)
        // The start screen looks the same in every appearance, its status bar
        // included, so the window is held dark there.
        .onChange(of: windowColorScheme, initial: true) { _, scheme in
            windowAppearance.hold(scheme)
        }
    }

    /// A plain button takes only the touches on its glyph; this one takes
    /// the whole 44-point square around it.
    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var isKiosk: Bool { pressing.state.screen.isKiosk }
    private var appearance: Appearance { pressing.state.screen.appearance }
    /// Dark on the start screen; the appearance on Now Playing, where nil
    /// (System) follows iOS.
    private var windowColorScheme: ColorScheme? {
        page == .nowPlaying ? appearance.colorScheme : .dark
    }
    /// The sheets' appearance. They inherit the window's, which is held dark
    /// on the start screen, so System is resolved to iOS's own setting.
    private var sheetColorScheme: ColorScheme {
        appearance.colorScheme ?? windowAppearance.system
    }
    private var hidesControls: Bool { pressing.state.hidesControls }
}

extension Appearance {
    /// Nil for System, so iOS's own setting applies.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// In kiosk mode Now Playing's icons fade out after 30 s without a touch,
    /// and any touch brings them back. They keep their place, so nothing on
    /// the screen moves.
    func kioskHidden(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            .animation(.easeInOut(duration: 0.4), value: hidden)
    }
}
