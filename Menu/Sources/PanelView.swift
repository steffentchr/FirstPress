import AppKit
import SwiftUI
import PressingCore
import PressingMenuCore

/// The panel, in the reference look: the current Track's title large and
/// bold with the artist lighter beneath, a divider, then History as a
/// numbered list. Everything the phone last sent stays on screen, greyed,
/// while it can't be reached. The footer's Rooms summary swaps the Rooms
/// view in place of History.
struct PanelView: View {
    let menu: PressingMenu
    @State private var showsRooms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(header: menu.header)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
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
            Divider()
            FooterView(roomsSummary: menu.roomsSummary, showRooms: { showsRooms.toggle() })
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .opacity(menu.connection == .connected ? 1 : 0.5)
        .frame(width: 340)
    }
}

private struct HeaderView: View {
    let header: PressingMenu.Header

    var body: some View {
        switch header {
        case .track(let track):
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .lookingForPressing:
            message("Looking for Pressing…")
        case .cantBeReached:
            message("The iPhone can't be reached")
        case .waitingForRecord:
            message("Waiting for a Record")
        case .recordNotIdentified:
            message("A Record is playing", detail: "Not identified yet")
        case .updatePressingMenu:
            message("Update Pressing Menu", detail: "Pressing on the iPhone is newer than this Pressing Menu.")
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
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The power button, which quits Pressing Menu and leaves Pressing on the
/// iPhone untouched, and on the right where Pressing plays, which opens the
/// Rooms view.
private struct FooterView: View {
    let roomsSummary: String
    let showRooms: () -> Void

    var body: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .help("Quit Pressing Menu")
            .accessibilityLabel("Quit Pressing Menu")
            Spacer()
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
