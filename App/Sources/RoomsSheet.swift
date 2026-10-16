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
        }
    }
}

/// One place the Record can play: its name, a line under it (the volume bar
/// while switched on), and a checkbox on the right. Tapping the name or the
/// checkbox switches it.
private struct OutputRow<Detail: View>: View {
    let name: String
    let isOn: Bool
    let toggle: () -> Void
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: toggle) {
                    Text(name)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                detail
            }
            Button(action: toggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn ? "On" : "Off")
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The Phone output: where the phone plays (its speaker, earphones or
/// AirPlay), chosen with the system route picker while it's on. The volume is
/// the system's, so there is no bar.
struct PhoneOutputRow: View {
    let pressing: Pressing

    var body: some View {
        let isOn = pressing.state.phoneOutput.isOn
        OutputRow(name: "This iPhone", isOn: isOn, toggle: { pressing.switchPhoneOutput(on: !isOn) }) {
            if isOn {
                HStack(spacing: 8) {
                    RoutePickerButton()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Where This iPhone plays")
                    Text("Speaker, earphones or AirPlay. Plays ahead of the Rooms.")
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
        OutputRow(name: room.name, isOn: room.isOn, toggle: { pressing.switchRoom(room.id, on: !room.isOn) }) {
            if let marker {
                Label(marker.text, systemImage: marker.symbol)
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
