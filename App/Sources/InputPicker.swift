import SwiftUI
import PressingCore

/// The input as one dropdown, in Settings. Shows "Not connected" while the
/// chosen input is missing, so it's clear why nothing is happening.
struct InputPicker: View {
    let pressing: Pressing

    private var input: InputState { pressing.state.input }

    var body: some View {
        Picker("Input", selection: Self.selection(pressing)) {
            if input.chosenID == nil {
                Text("Choose…").tag(AudioInputDevice.ID?.none)
            }
            if let chosen = input.chosenID, !input.available.contains(where: { $0.id == chosen }) {
                Text("Not connected").tag(AudioInputDevice.ID?.some(chosen))
            }
            InputChoices(input: input)
        }
        .pickerStyle(.menu)
    }

    /// Choosing an input switches to it at once.
    static func selection(_ pressing: Pressing) -> Binding<AudioInputDevice.ID?> {
        Binding(
            get: { pressing.state.input.chosenID },
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

/// The connected inputs, as the choices of a picker tagged by id.
private struct InputChoices: View {
    let input: InputState

    var body: some View {
        ForEach(input.available) { device in
            Text(InputPicker.label(device)).tag(AudioInputDevice.ID?.some(device.id))
        }
    }
}

/// The chosen input's name, on the choose-input and waiting screen. Tapping
/// it opens the same choices as Settings' dropdown. With no input chosen it
/// reads as a prompt; a missing input is named and marked not connected.
struct InputNameMenu: View {
    let pressing: Pressing

    private var input: InputState { pressing.state.input }

    var body: some View {
        Menu {
            Picker("Input", selection: InputPicker.selection(pressing)) {
                InputChoices(input: input)
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if input.chosenID == nil {
            Label("Choose the input", systemImage: "chevron.up.chevron.down")
                .labelStyle(TrailingIcon())
        } else if input.status == .missing {
            VStack(spacing: 2) {
                Label(input.chosenName ?? "The input", systemImage: "chevron.up.chevron.down")
                    .labelStyle(TrailingIcon())
                Text("Not connected")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } else {
            Label(input.chosenName ?? "Input", systemImage: "chevron.up.chevron.down")
                .labelStyle(TrailingIcon())
        }
    }
}

/// The title, then a small icon: reads as a dropdown.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.footnote)
        }
    }
}
