import SwiftUI
import UIKit
import PressingCore

struct SettingsView: View {
    let pressing: Pressing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var input: InputState { pressing.state.input }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Input", selection: chosenInput) {
                        if input.chosenID == nil {
                            Text("None").tag(AudioInputDevice.ID?.none)
                        }
                        if let chosen = input.chosenID, !input.available.contains(where: { $0.id == chosen }) {
                            Text("Not connected").tag(AudioInputDevice.ID?.some(chosen))
                        }
                        ForEach(input.available) { device in
                            Text(Self.label(device)).tag(AudioInputDevice.ID?.some(device.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Input")
                } footer: {
                    Text("Pressing only listens to the input chosen here. It never switches to the built-in microphone on its own.")
                }

                Section("Permissions") {
                    Button("Microphone access") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private var chosenInput: Binding<AudioInputDevice.ID?> {
        Binding(
            get: { input.chosenID },
            set: { id in
                if let id { pressing.chooseInput(id) }
            }
        )
    }

    private static func label(_ device: AudioInputDevice) -> String {
        switch device.kind {
        case .usb: "\(device.name) (USB)"
        case .builtInMic: "\(device.name) (picks up the room)"
        case .other: device.name
        }
    }
}
