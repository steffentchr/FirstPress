import SwiftUI
import PressingCore

/// Settings › Detection: calibrate against the live level and noise floor
/// (README › Calibrate detection).
struct DetectionSettingsView: View {
    let pressing: Pressing
    @State private var refusal: String?

    private var detection: DetectionSettings { pressing.state.detection }
    private var input: InputState { pressing.state.input }

    var body: some View {
        Form {
            Section {
                LevelMeterView(level: input.level, noiseFloor: input.noiseFloor, threshold: detection.threshold)
                    .padding(.vertical, 4)
            } header: {
                Text("Level")
            } footer: {
                Text("The white tick is the noise floor, the orange tick the threshold. Calibrate with the needle in the run-out groove.")
            }

            Section {
                Stepper("Threshold \(Int(detection.threshold)) dBFS", value: detectionBinding(\.threshold), in: -80...(-20), step: 1)
                Stepper("Start delay \(Self.seconds(detection.startDelay))", value: detectionBinding(\.startDelay), in: 0.5...10, step: 0.5)
                Stepper("Flip after \(Self.seconds(detection.flipThreshold))", value: detectionBinding(\.flipThreshold), in: 3...120, step: 1)
                Stepper("Stop delay \(Self.seconds(detection.stopDelay))", value: detectionBinding(\.stopDelay), in: 5...600, step: 5)
                // Pitch-shifted playback isn't supported: Tracks stop matching.
                Label("Keep the deck's pitch control at zero, so Tracks are identified and reach Last.fm correctly.", systemImage: "dial.low")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                if let refusal {
                    Text(refusal).foregroundStyle(.orange)
                } else {
                    Text("Set the threshold clearly above the noise floor and below the quietest music. A Record starts once the level stays above it for the start delay, and ends with a Flip after that long below it. The Session ends once the silence reaches the stop delay, counted from when it began, unless a new Record starts.")
                }
            }
        }
        .sheetPage("Detection")
    }

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

    private static func seconds(_ value: TimeInterval) -> String {
        value.rounded() == value ? "\(Int(value)) s" : String(format: "%.1f s", value)
    }
}

/// Horizontal meter from −80 to 0 dBFS with ticks at the noise floor (white) and the start threshold (orange).
struct LevelMeterView: View {
    let level: Double?
    let noiseFloor: Double?
    /// The start threshold from Settings, marked so it can be set above the noise floor.
    let threshold: Double

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
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * Self.fraction(threshold))
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
