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
                HStack(spacing: 20) {
                    Spacer()
                    // Before any input is chosen, no Rooms are looked for yet.
                    if page != .chooseInput(.noneChosen) {
                        Button("Rooms", systemImage: "hifispeaker.2") { showingRooms = true }
                    }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.plain)
                .foregroundStyle(iconColor)
                .frame(height: 44)
                .padding(.horizontal, 20)
                .kioskHidden(hidesControls)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(pressing: pressing)
                    .screenBlanker(pressing)
            }
            .sheet(isPresented: $showingRooms) {
                RoomsSheet(pressing: pressing)
                    .screenBlanker(pressing)
            }
        }
        .screenBlanker(pressing)
        // Kiosk mode: no clock, battery or other status bar, and the home
        // indicator fades away until the screen is touched near it.
        .statusBarHidden(isKiosk)
        .persistentSystemOverlays(isKiosk ? .hidden : .automatic)
    }

    private var isKiosk: Bool { pressing.state.screen.isKiosk }
    private var hidesControls: Bool { pressing.state.hidesControls }
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
