import SwiftUI
import PressingCore

struct MainView: View {
    let pressing: Pressing
    @State private var showingSettings = false

    private var input: InputState { pressing.state.input }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                InputStatusView(input: input)
                LevelMeterView(level: input.level, noiseFloor: input.noiseFloor)
                Spacer()
            }
            .padding()
            .navigationTitle("Pressing")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(pressing: pressing)
            }
        }
    }
}

struct InputStatusView: View {
    let input: InputState

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(isPresent ? Color.primary : Color.orange)
    }

    private var isPresent: Bool { input.status == .present }

    private var chosenName: String {
        input.available.first { $0.id == input.chosenID }?.name ?? "The chosen input"
    }

    private var message: String {
        switch input.status {
        case .notChosen: "Choose the input in Settings."
        case .missing: "The chosen input isn't connected. Check the cable."
        case .present: chosenName
        case .interrupted: "Another app is using audio."
        case .permissionDenied: "Pressing can't use the input. Allow microphone access in Settings."
        case .unsupportedSampleRate(let rate): "The input runs at \(Int(rate)) Hz. Pressing takes 44.1 or 48 kHz."
        case .failed(let reason): reason
        }
    }

    private var symbol: String {
        switch input.status {
        case .present: "cable.connector"
        case .notChosen: "questionmark.circle"
        default: "exclamationmark.triangle"
        }
    }
}

/// Horizontal meter from −80 to 0 dBFS with a tick at the noise floor.
struct LevelMeterView: View {
    let level: Double?
    let noiseFloor: Double?

    private static let range = -80.0...0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.green)
                        .frame(width: geometry.size.width * Self.fraction(level))
                    if let noiseFloor {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .offset(x: geometry.size.width * Self.fraction(noiseFloor))
                    }
                }
            }
            .frame(height: 16)
            .animation(.linear(duration: 0.1), value: level)

            HStack {
                Text("Level \(Self.format(level))")
                Spacer()
                Text("Noise floor \(Self.format(noiseFloor))")
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private static func fraction(_ dBFS: Double?) -> CGFloat {
        guard let dBFS else { return 0 }
        let clamped = min(max(dBFS, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private static func format(_ dBFS: Double?) -> String {
        guard let dBFS else { return "–" }
        return "\(Int(dBFS.rounded())) dBFS"
    }
}
