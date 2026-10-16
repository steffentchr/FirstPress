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

    /// White over the start screen's orange; the system tint on Now Playing.
    private var iconTint: Color? { page == .nowPlaying ? nil : .white }

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
            .toolbar {
                // Before any input is chosen, no Rooms are looked for yet.
                if page != .chooseInput(.noneChosen) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Rooms", systemImage: "hifispeaker.2") { showingRooms = true }
                            .tint(iconTint)
                    }
                    .withoutGlass()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                        .tint(iconTint)
                }
                .withoutGlass()
            }
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
}

extension ToolbarContent {
    /// Just the icon: no Liquid Glass background behind it (iOS 26 and later;
    /// earlier versions draw none anyway).
    @ToolbarContentBuilder
    func withoutGlass() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
