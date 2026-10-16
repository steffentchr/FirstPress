import SwiftUI
import PressingCore

/// The Sonos Rooms, each with an on/off switch and a volume.
struct RoomsView: View {
    let pressing: Pressing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rooms").font(.headline)
            if pressing.state.rooms.isEmpty {
                Text("Looking for Sonos Rooms… If none appear, allow Local Network access in Settings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(pressing.state.rooms) { room in
                RoomRow(room: room, pressing: pressing)
            }
        }
    }
}

struct RoomRow: View {
    let room: RoomState
    let pressing: Pressing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(room.name, isOn: Binding(
                get: { room.isOn },
                set: { pressing.switchRoom(room.id, on: $0) }
            ))
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
}
