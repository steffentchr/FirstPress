import SwiftUI
import UIKit
import PressingCore

/// Opened from the gear: the common settings at the top, and Detection and
/// Permissions, rarely touched once set, in submenus.
struct SettingsView: View {
    let pressing: Pressing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InputPicker(pressing: pressing)
                } footer: {
                    Text("Pressing only listens to the input chosen here. It never switches to the built-in microphone on its own.")
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

                LastFmSection(pressing: pressing)

                Section {
                    NavigationLink("Detection") { DetectionSettingsView(pressing: pressing) }
                    NavigationLink("Permissions") { PermissionsView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
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
}

/// Settings › Permissions: shortcuts to Pressing's page in the Settings app.
struct PermissionsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                // Both switches are on Pressing's own page in the Settings app.
                Button("Microphone access") { openAppSettings() }
                Button("Local network access") { openAppSettings() }
            } footer: {
                Text("Pressing needs the microphone to hear the deck's input, and local network access to find your Sonos Rooms and play to them.")
            }
        }
        .navigationTitle("Permissions")
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
