import SwiftUI
import PressingCore

/// Opened from the speaker icon: the Sonos Rooms, each with an on/off switch
/// and a volume, and why a Room may be quiet. Works mid-Session too.
struct RoomsSheet: View {
    let pressing: Pressing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if pressing.state.rooms.isEmpty {
                    Text("Looking for Sonos Rooms… If none appear, allow local network access in Settings › Permissions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pressing.state.rooms) { room in
                    RoomRow(room: room, pressing: pressing)
                }
            }
            .navigationTitle("Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct RoomRow: View {
    let room: RoomState
    let pressing: Pressing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { room.isOn },
                set: { pressing.switchRoom(room.id, on: $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                    if let marker {
                        Label(marker.text, systemImage: marker.symbol)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(room.volume) },
                        set: { pressing.setVolume(Int($0.rounded()), for: room.id) }
                    ),
                    in: 0...100,
                    step: 1
                )
                Text("\(room.volume)")
                    .font(.footnote.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .opacity(room.isOn ? 1 : 0.4)
        }
    }

    /// Why a switched-on Room may be quiet.
    private var marker: (text: String, symbol: String)? {
        if !room.isReachable {
            return ("Can't be reached", "wifi.exclamationmark")
        }
        if room.isSteppedBack {
            return ("Taken over in the Sonos app. Switch off and on to take it back.", "hand.raised")
        }
        return nil
    }
}
