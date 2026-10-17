import AppKit
import SwiftUI
import FirstPressCore
import FirstPressMenuCore

/// The panel, in the reference look: the current Track's cover on the
/// left, its title large and bold with the artist lighter beneath and the
/// album, once known, quieter still, then a divider and History as a numbered list. While no phone
/// is connected it says, small, that it's looking for First Press; after a
/// drop-out the last Track and History stay on screen, greyed, with that
/// line beneath the Track. The footer is never greyed. Its Rooms summary
/// swaps the Rooms view in place of History.
struct PanelView: View {
    let menu: FirstPressMenu
    @State private var showsRooms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView(header: menu.header)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, menu.showsLookingLine ? 8 : 16)
                if menu.showsLookingLine {
                    LookingText()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                if showsRooms {
                    Divider()
                        .padding(.horizontal, 20)
                    RoomsView(menu: menu, back: { showsRooms = false })
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                } else if !menu.history.isEmpty {
                    Divider()
                        .padding(.horizontal, 20)
                    HistoryList(tracks: menu.history)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
            }
            // Only what the phone sent is greyed, never the footer.
            .opacity(menu.connection == .connected ? 1 : 0.5)
            Divider()
            FooterView(roomsSummary: menu.roomsSummary, showRooms: { showsRooms.toggle() })
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        // No notifications while the panel is open: the Track is in view.
        .background(PanelVisibility { menu.isPanelOpen = $0 })
    }
}

/// "Looking for First Press on your iPhone…", small and secondary: the whole
/// header while no phone is connected, or a line beneath a kept Track.
private struct LookingText: View {
    var body: some View {
        Text("Looking for First Press on your iPhone…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeaderView: View {
    let header: FirstPressMenu.Header

    var body: some View {
        switch header {
        case .track(let track):
            HStack(alignment: .top, spacing: 12) {
                CoverView(url: track.artworkURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // The album often arrives a moment later, from Last.fm: its
                    // line appears beneath without moving the title or artist.
                    if let album = track.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .findsOnClick(track)
        case .lookingForFirstPress:
            LookingText()
        case .waitingForRecord:
            message("Waiting for a Record")
        case .recordNotIdentified:
            message("A Record is playing", detail: "Not identified yet")
        case .betweenSides(let lastTrack):
            // The last Track's title kept small beneath, if there was one.
            message("Between sides", detail: lastTrack?.title)
        case .updateFirstPressMenu:
            message("Update First Press Menu", detail: "First Press on the iPhone is newer than this First Press Menu.")
        }
    }

    private func message(_ text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 22, weight: .bold))
            if let detail {
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The current Track's cover, square with rounded corners as on the
/// phone. A neutral square of the same size stands in while it loads, or
/// when there is none, so nothing moves when it arrives.
private struct CoverView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// History: numbered 1 to 10, newest first, the title with the artist in a
/// quieter style.
private struct HistoryList: View {
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .findsOnClick(track)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// On the left, the power button, which quits First Press Menu and leaves
/// First Press on the iPhone untouched, and the gear, which opens Settings. On
/// the right, where First Press plays, which opens the Rooms view: shown only
/// while a phone is connected.
private struct FooterView: View {
    let roomsSummary: String?
    let showRooms: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help("Quit First Press Menu")
            .accessibilityLabel("Quit First Press Menu")
            Button {
                openWindow(id: SettingsView.windowID)
                // A menu-bar app isn't in front by itself: bring Settings forward.
                NSApplication.shared.activate()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            if let roomsSummary {
                Button(action: showRooms) {
                    HStack(spacing: 5) {
                        Image(systemName: "hifispeaker.2")
                        Text(roomsSummary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Rooms")
                .accessibilityLabel("Rooms: \(roomsSummary)")
            }
        }
    }
}

/// Clicking a Track opens the chosen service's search for it straight away,
/// with no menu. It looks clickable: a pointing hand and a soft highlight
/// on hover. A right-click does nothing.
private struct FindsOnClick: ViewModifier {
    let track: Track
    @Environment(MenuSettings.self) private var settings
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .pointerStyle(.link)
            .onTapGesture { find() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Finds it in \(settings.findTracksIn.name)")
            .accessibilityAction { find() }
    }

    private func find() {
        NSWorkspace.shared.open(settings.findTracksIn.searchURL(for: track))
    }
}

private extension View {
    func findsOnClick(_ track: Track) -> some View {
        modifier(FindsOnClick(track: track))
    }
}

extension TrackSearchService {
    var name: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }
}
