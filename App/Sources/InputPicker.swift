import SwiftUI
import PressingCore

/// The input as one dropdown. Shows "Not connected" while the chosen input
/// is missing, so it's clear why nothing is happening.
struct InputPicker: View {
    let pressing: Pressing

    private var input: InputState { pressing.state.input }

    var body: some View {
        Picker("Input", selection: chosenInput) {
            if input.chosenID == nil {
                Text("Choose…").tag(AudioInputDevice.ID?.none)
            }
            if let chosen = input.chosenID, !input.available.contains(where: { $0.id == chosen }) {
                Text("Not connected").tag(AudioInputDevice.ID?.some(chosen))
            }
            ForEach(input.available) { device in
                Text(Self.label(device)).tag(AudioInputDevice.ID?.some(device.id))
            }
        }
        .pickerStyle(.menu)
    }

    private var chosenInput: Binding<AudioInputDevice.ID?> {
        Binding(
            get: { input.chosenID },
            set: { id in
                if let id { pressing.chooseInput(id) }
            }
        )
    }

    static func label(_ device: AudioInputDevice) -> String {
        switch device.kind {
        case .usb: "\(device.name) (USB)"
        case .builtInMic: "\(device.name) (picks up the room)"
        case .other: device.name
        }
    }
}
