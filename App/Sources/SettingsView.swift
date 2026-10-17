import SwiftUI
import UIKit
import FirstPressCore

/// Opened from the gear: the common settings at the top, and Detection and
/// Permissions, rarely touched once set, in submenus.
struct SettingsView: View {
    let firstPress: FirstPress

    var body: some View {
        FirstPressSheet(title: "Settings") {
            Form {
                Section {
                    InputPicker(firstPress: firstPress)
                } footer: {
                    Text("First Press only listens to the input chosen here. It never switches to the built-in microphone on its own.")
                }

                Section {
                    AppearanceRow(firstPress: firstPress)
                    Picker("Blank screen", selection: blankAfter) {
                        ForEach(Self.blankAfterChoices, id: \.self) { choice in
                            Text(Self.label(choice)).tag(choice)
                        }
                    }
                    CheckboxRow(name: "Kiosk mode", nameFont: .body, isOn: firstPress.state.screen.isKiosk) {
                        firstPress.setKiosk(!firstPress.state.screen.isKiosk)
                    }
                } header: {
                    Text("Screen")
                } footer: {
                    Text("A blank screen protects the display. It never blanks while a Record is playing. Touch it, or start a Record, to wake it. Kiosk mode lets First Press take the whole screen, without the clock, battery and other status icons, and Now Playing's icons hide until you touch the screen. To keep others from leaving the app, also start Guided Access.")
                }

                LastFmSection(firstPress: firstPress)

                Section {
                    NavigationLink("Detection") { DetectionSettingsView(firstPress: firstPress) }
                    NavigationLink("Permissions") { PermissionsView() }
                }
            }
        }
    }

    private var blankAfter: Binding<BlankAfter> {
        Binding(
            get: { firstPress.state.screen.blankAfter },
            set: { firstPress.setBlankAfter($0) }
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

/// System, Light or Dark, with the icons First Press Menu uses for the same
/// choice. The start screen and the blank screen look the same in all three.
private struct AppearanceRow: View {
    let firstPress: FirstPress

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance")
                Text("System follows iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Picker("Appearance", selection: appearance) {
                Image(systemName: "circle.lefthalf.filled")
                    .accessibilityLabel("System")
                    .tag(Appearance.system)
                Image(systemName: "sun.max")
                    .accessibilityLabel("Light")
                    .tag(Appearance.light)
                Image(systemName: "moon")
                    .accessibilityLabel("Dark")
                    .tag(Appearance.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var appearance: Binding<Appearance> {
        Binding(
            get: { firstPress.state.screen.appearance },
            set: { firstPress.setAppearance($0) }
        )
    }
}

/// Settings › Permissions: shortcuts to First Press's page in the Settings app.
struct PermissionsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                // Both switches are on First Press's own page in the Settings app.
                Button("Microphone access") { openAppSettings() }
                Button("Local network access") { openAppSettings() }
            } footer: {
                Text("First Press needs the microphone to hear the deck's input, and local network access to find your Sonos Rooms and play to them.")
            }
        }
        .sheetPage("Permissions")
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
