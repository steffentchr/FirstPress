import SwiftUI
import PressingCore

/// The app's root: the page the core names, with History a swipe away.
/// Swipe left to History, right to come back.
struct RootView: View {
    let pressing: Pressing
    let audioInput: AVAudioSessionInput

    var body: some View {
        TabView {
            HomeView(pressing: pressing, audioInput: audioInput)
            HistoryView(pressing: pressing)
                .screenBlanker(pressing)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

/// Choose input, waiting or Now Playing, under a gear and a speaker icon.
///
/// The sheets hang off this view rather than off each page, so an open
/// Settings or Rooms sheet stays open when a Record starts or a Session ends
/// underneath it.
struct HomeView: View {
    let pressing: Pressing
    let audioInput: AVAudioSessionInput
    @State private var showingSettings = false
    @State private var showingRooms = false

    private var page: Page { pressing.state.page }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .chooseInput(let reason):
                    WaitingView(pressing: pressing, audioInput: audioInput, chooseInput: reason)
                case .waiting:
                    WaitingView(pressing: pressing, audioInput: audioInput, chooseInput: nil)
                case .nowPlaying:
                    NowPlayingView(play: pressing.state.play)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.4), value: page)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Before any input is chosen, no Rooms are looked for yet.
                    if page != .chooseInput(.noneChosen) {
                        Button("Rooms", systemImage: "hifispeaker.2") { showingRooms = true }
                    }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
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
    }
}
