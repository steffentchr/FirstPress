import SwiftUI
import UIKit
import PressingCore

/// The one screen shown while no Record plays. It asks for an input when
/// none is chosen or the chosen one isn't connected, and otherwise waits
/// quietly for a Record.
struct WaitingView: View {
    let pressing: Pressing
    let audioInput: AVAudioSessionInput
    /// Why an input is needed, or nil once the input is ready.
    let chooseInput: Page.Reason?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if let chooseInput {
                choosing(chooseInput)
            } else {
                waiting
            }
            Spacer()
        }
        .padding()
        .task(id: chooseInput) {
            // Listing the inputs needs the microphone, so ask here and not before.
            if chooseInput != nil { await audioInput.requestPermission() }
        }
    }

    private func choosing(_ reason: Page.Reason) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "cable.connector")
                .font(.system(size: 56))
                .foregroundStyle(reason == .notConnected ? Color.orange : Color.secondary)
            Text(reason == .noneChosen ? "Choose the input" : "The input isn't connected")
                .font(.title2.bold())
            Text(reason == .noneChosen
                 ? "Choose the record deck's input. Pressing only listens to the input chosen here."
                 : "Check the cable, or choose another input.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            InputNameMenu(pressing: pressing)
                .buttonStyle(.bordered)
            if audioInput.isPermissionDenied {
                Button("Allow microphone access") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Drop the needle to start.")
                .foregroundStyle(.secondary)
            InputNameMenu(pressing: pressing)
                .font(.subheadline)
            // Only a problem is worth a word here; a ready input says nothing.
            if pressing.state.input.status != .present {
                InputStatusView(input: pressing.state.input)
            }
        }
    }
}

/// Why the chosen input isn't capturing.
struct InputStatusView: View {
    let input: InputState

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
    }

    private var message: String {
        switch input.status {
        case .notChosen: "Choose the input in Settings."
        case .missing: "The chosen input isn't connected. Check the cable."
        case .present: ""
        case .interrupted: "Another app is using audio."
        case .permissionDenied: "Pressing can't use the input. Allow microphone access in Settings › Permissions."
        case .unsupportedSampleRate(let rate): "The input runs at \(Int(rate)) Hz. Pressing takes 44.1 or 48 kHz."
        case .failed(let reason): reason
        }
    }
}
