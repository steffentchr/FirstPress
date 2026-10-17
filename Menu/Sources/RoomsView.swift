import SwiftUI
import PressingCore
import PressingMenuCore

/// The phone's Rooms sheet, inside the panel, in place of History: This
/// iPhone first, then every Sonos Room Pressing has found. Ticking a box
/// switches it at once, on the phone and on the speakers; a switched-on Room
/// has a volume slider. Disabled while the iPhone can't be reached.
struct RoomsView: View {
    let menu: PressingMenu
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) {
                Label("Rooms", systemImage: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
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

/// This iPhone: the Phone output's switch and where it plays. The receiver
/// itself is picked on the phone; iOS offers no way to choose it from here.
private struct PhoneOutputRow: View {
    let phoneOutput: MenuSnapshot.PhoneOutput
    let menu: PressingMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { phoneOutput.isOn }, set: { menu.switchPhoneOutput(on: $0) })) {
                Text("This iPhone")
                    .font(.system(size: 16, weight: .semibold))
            }
            .toggleStyle(.checkbox)
            Group {
                Text(phoneOutput.whereItPlays ?? "Its speaker, earphones or AirPlay")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("The AirPlay receiver is chosen on the iPhone.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 22)
        }
    }
}

private struct RoomRow: View {
    let room: MenuSnapshot.Room
    let menu: PressingMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { room.isOn }, set: { menu.switchRoom(room.id, on: $0) })) {
                Text(room.name)
                    .font(.system(size: 16, weight: .semibold))
            }
            .toggleStyle(.checkbox)
            Group {
                if let marker = room.marker {
                    Label(marker.text, systemImage: marker.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if room.isOn {
                    HStack(spacing: 8) {
                        Image(systemName: room.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Slider(
                            value: Binding(
                                get: { Double(room.volume) },
                                set: { menu.dragVolume(Int($0.rounded()), for: room.id) }
                            ),
                            in: 0...100,
                            step: 1
                        ) { editing in
                            guard !editing, let volume = menu.room(room.id)?.volume else { return }
                            menu.setVolume(volume, for: room.id)
                        }
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
            .padding(.leading, 22)
        }
    }
}

private extension RoomMarker {
    var text: String {
        switch self {
        case .cantBeReached: "Can't be reached"
        case .takenOverInSonosApp: "Taken over in the Sonos app. Switch off and on to take it back."
        }
    }

    var symbol: String {
        switch self {
        case .cantBeReached: "wifi.exclamationmark"
        case .takenOverInSonosApp: "hand.raised"
        }
    }
}
