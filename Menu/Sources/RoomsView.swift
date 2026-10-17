import SwiftUI
import PressingCore
import PressingMenuCore

/// The phone's Rooms sheet, inside the panel, in place of History: This
/// iPhone first, then every Sonos Room Pressing has found. Ticking a box
/// switches it at once, on the phone and on the speakers; a switched-on Room
/// has a volume slider. Disabled while no phone is connected.
///
/// Everything lines up on two columns: the checkboxes (and the back
/// chevron above them), then the names (and the "Rooms" title).
struct RoomsView: View {
    let menu: PressingMenu
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) {
                HStack(spacing: Columns.spacing) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: Columns.checkbox, alignment: .leading)
                    Text("Rooms")
                        .font(.system(size: 15, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Back to History")

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let phoneOutput = menu.phoneOutput {
                        PhoneOutputRow(phoneOutput: phoneOutput, menu: menu)
                        Divider()
                    }
                    if menu.rooms.isEmpty {
                        Text("Looking for Sonos Rooms…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(menu.rooms) { room in
                        RoomRow(room: room, menu: menu)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(!menu.canControl)
        }
    }
}

/// The checkbox column and the gap after it. The names, the "Rooms" title
/// and everything beneath a name start at `Columns.names`.
private enum Columns {
    static let checkbox: CGFloat = 16
    static let spacing: CGFloat = 6
    static var names: CGFloat { checkbox + spacing }
}

/// A checkbox in its column, then the name. Clicking the name ticks the box
/// too, as a checkbox's own title would.
private struct CheckboxRow: View {
    let name: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: Columns.spacing) {
            Toggle(name, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Columns.checkbox, alignment: .leading)
            Text(name)
                .font(.system(size: 16, weight: .semibold))
                .onTapGesture { set(!isOn) }
                .accessibilityHidden(true)
        }
    }
}

/// This iPhone: the Phone output's switch and where it plays. The receiver
/// itself is picked on the phone; iOS offers no way to choose it from here.
private struct PhoneOutputRow: View {
    let phoneOutput: MenuSnapshot.PhoneOutput
    let menu: PressingMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CheckboxRow(name: "This iPhone", isOn: phoneOutput.isOn) { menu.switchPhoneOutput(on: $0) }
            Group {
                Text(phoneOutput.whereItPlays ?? "Its speaker, earphones or AirPlay")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("The AirPlay receiver is chosen on the iPhone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, Columns.names)
        }
    }
}

private struct RoomRow: View {
    let room: MenuSnapshot.Room
    let menu: PressingMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CheckboxRow(name: room.name, isOn: room.isOn) { menu.switchRoom(room.id, on: $0) }
            Group {
                if let marker = room.marker {
                    Label(marker.text, systemImage: marker.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if room.isOn {
                    HStack(spacing: 8) {
                        Image(systemName: room.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        // Continuous, so macOS draws no tick marks under the
                        // track; the volume is rounded to a whole number.
                        Slider(
                            value: Binding(
                                get: { Double(room.volume) },
                                set: { menu.dragVolume(Int($0.rounded()), for: room.id) }
                            ),
                            in: 0...100,
                            onEditingChanged: { editing in
                                guard !editing, let volume = menu.room(room.id)?.volume else { return }
                                menu.setVolume(volume, for: room.id)
                            }
                        )
                        .controlSize(.small)
                        .accessibilityLabel("Volume in \(room.name)")
                        .accessibilityValue("\(room.volume)")
                        Text("\(room.volume)")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.leading, Columns.names)
        }
    }
}
