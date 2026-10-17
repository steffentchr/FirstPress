import AVKit
import SwiftUI
import PressingCore

/// Opened from the speaker icon: "This iPhone" (the Phone output), then the
/// Sonos Rooms. Ticking a Room's checkbox switches it on at once (there's
/// nothing to apply), and only a switched-on Room shows its volume bar.
/// Works mid-Session too.
struct RoomsSheet: View {
    let pressing: Pressing

    var body: some View {
        PressingSheet(title: "Rooms") {
            List {
                PhoneOutputRow(pressing: pressing)
                if pressing.state.rooms.isEmpty {
                    Text("Looking for Sonos Rooms… If none appear, allow local network access in Settings › Permissions.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(pressing.state.rooms) { room in
                    RoomRow(room: room, pressing: pressing)
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}

/// The Phone output: where the phone plays (its speaker, earphones or
/// AirPlay), chosen with the system route picker while it's on. The volume is
/// the system's, so there is no bar.
struct PhoneOutputRow: View {
    let pressing: Pressing

    var body: some View {
        let isOn = pressing.state.phoneOutput.isOn
        CheckboxRow(name: "This iPhone", isOn: isOn, toggle: { pressing.switchPhoneOutput(on: !isOn) }) {
            if isOn {
                HStack(spacing: 8) {
                    RoutePickerButton()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Where This iPhone plays")
                    Text(pressing.state.phoneOutput.route.map { "Plays on \($0.label), ahead of the Rooms." }
                        ?? "Speaker, earphones or AirPlay. Plays ahead of the Rooms.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Its speaker, earphones or AirPlay")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The system's AirPlay and Bluetooth route picker.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = .tintColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct RoomRow: View {
    let room: RoomState
    let pressing: Pressing

    var body: some View {
        CheckboxRow(name: room.name, isOn: room.isOn, toggle: { pressing.switchRoom(room.id, on: !room.isOn) }) {
            if let marker = room.marker {
                Label(marker.text, systemImage: marker.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if room.isOn {
                HStack(spacing: 10) {
                    Image(systemName: room.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Slider(
                        value: Binding(
                            get: { Double(room.volume) },
                            set: { pressing.setVolume(Int($0.rounded()), for: room.id) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    .accessibilityLabel("Volume")
                    Text("\(room.volume)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}
