import SwiftUI
import UIKit
import PressingCore

struct SettingsView: View {
    let pressing: Pressing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var refusal: String?

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

                Section {
                    Stepper("Threshold \(Int(detection.threshold)) dBFS", value: detectionBinding(\.threshold), in: -80...(-20), step: 1)
                    Stepper("Start delay \(Self.seconds(detection.startDelay))", value: detectionBinding(\.startDelay), in: 0.5...10, step: 0.5)
                    Stepper("Flip after \(Self.seconds(detection.flipThreshold))", value: detectionBinding(\.flipThreshold), in: 3...120, step: 1)
                    Stepper("Stop delay \(Self.seconds(detection.stopDelay))", value: detectionBinding(\.stopDelay), in: 5...600, step: 5)
                } header: {
                    Text("Detection")
                } footer: {
                    if let refusal {
                        Text(refusal).foregroundStyle(.orange)
                    } else {
                        Text("Set the threshold clearly above the noise floor and below the quietest music. A Record starts once the level stays above it for the start delay, and ends with a Flip after that long below it. The Session ends once the silence reaches the stop delay, counted from when it began, unless a new Record starts.")
                    }
                }

                Section {
                    Picker("Blank screen", selection: blankAfter) {
                        ForEach(Self.blankAfterChoices, id: \.self) { choice in
                            Text(Self.label(choice)).tag(choice)
                        }
                    }
                } header: {
                    Text("Screen")
                } footer: {
                    Text("A blank screen protects the display. It never blanks while a Record is playing. Touch it, or start a Record, to wake it.")
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

    private var detection: DetectionSettings { pressing.state.detection }

    private func detectionBinding(_ keyPath: WritableKeyPath<DetectionSettings, Double>) -> Binding<Double> {
        Binding(
            get: { detection[keyPath: keyPath] },
            set: { value in
                var changed = detection
                changed[keyPath: keyPath] = value
                do {
                    try pressing.setDetection(changed)
                    refusal = nil
                } catch {
                    refusal = "The stop delay must be longer than the Flip threshold, or a Session could end before its Record."
                }
            }
        )
    }

    private var blankAfter: Binding<BlankAfter> {
        Binding(
            get: { pressing.state.screen.blankAfter },
            set: { pressing.setBlankAfter($0) }
        )
    }

    private static let blankAfterChoices: [BlankAfter] = [.after(60), .after(2 * 60), .after(5 * 60), .after(10 * 60), .after(30 * 60), .never]

    private static func label(_ blankAfter: BlankAfter) -> String {
        switch blankAfter {
        case .never: "Never"
        case .after(let seconds):
            Int(seconds / 60) == 1 ? "After 1 minute of silence" : "After \(Int(seconds / 60)) minutes of silence"
        }
    }

    private static func seconds(_ value: TimeInterval) -> String {
        value.rounded() == value ? "\(Int(value)) s" : String(format: "%.1f s", value)
    }

    private static func label(_ device: AudioInputDevice) -> String {
        switch device.kind {
        case .usb: "\(device.name) (USB)"
        case .builtInMic: "\(device.name) (picks up the room)"
        case .other: device.name
        }
    }
}
