import Foundation

/// Converts stereo audio from the input's rate to the stream's 44.1 kHz.
///
/// A 44.1 kHz input passes through untouched. Anything else goes through a
/// windowed-sinc low-pass interpolator (32 taps, Blackman window, cutoff just
/// under the output's Nyquist), which keeps the audio band flat and stops
/// 48 kHz content above 22.05 kHz from folding back as aliasing. State carries
/// across buffers, so buffer boundaries are inaudible. Latency is 16 input samples.
struct Resampler {
    let inputRate: Double
    let outputRate: Double

    /// Taps either side of the interpolation point.
    private static let halfTaps = 16
    /// Sub-sample positions the filter is tabulated at.
    private static let phases = 1024

    private let step: Double
    private let table: [[Float]]
    private var left: [Float]
    private var right: [Float]
    /// Position of the next output sample, in input samples from the start of `left`.
    private var position: Double

    init(inputRate: Double, outputRate: Double = MP3.sampleRate) {
        self.inputRate = inputRate
        self.outputRate = outputRate
        step = inputRate / outputRate
        let halfTaps = Self.halfTaps
        // Prime with silence so the first output sample sits on input sample 0.
        left = Array(repeating: 0, count: halfTaps)
        right = left
        position = Double(halfTaps)
        guard inputRate != outputRate else {
            table = []
            return
        }
        // Cutoff as a fraction of the input rate: 95 % of the lower Nyquist.
        let cutoff = 0.95 * 0.5 * min(inputRate, outputRate) / inputRate
        table = (0...Self.phases).map { phase in
            let fraction = Double(phase) / Double(Self.phases)
            let taps = (0..<(2 * halfTaps)).map { tap -> Double in
                // Distance from the interpolation point to this input sample.
                let x = Double(tap - halfTaps + 1) - fraction
                let sinc = x == 0 ? 1 : sin(2 * .pi * cutoff * x) / (2 * .pi * cutoff * x)
                let n = (x + Double(halfTaps)) / Double(2 * halfTaps)
                let window = 0.42 - 0.5 * cos(2 * .pi * n) + 0.08 * cos(4 * .pi * n)
                return sinc * window
            }
            // Normalise each phase so a constant level stays exactly constant.
            let sum = taps.reduce(0, +)
            return taps.map { Float($0 / sum) }
        }
    }

    mutating func process(left newLeft: [Float], right newRight: [Float]) -> (left: [Float], right: [Float]) {
        guard inputRate != outputRate else { return (newLeft, newRight) }
        left += newLeft
        right += newRight
        var outLeft: [Float] = []
        var outRight: [Float] = []
        let halfTaps = Self.halfTaps
        outLeft.reserveCapacity(Int(Double(newLeft.count) / step) + 1)
        outRight.reserveCapacity(outLeft.capacity)
        // Each output needs input up to floor(position) + halfTaps.
        while Int(position) + halfTaps < left.count {
            let base = Int(position)
            let taps = table[Int(((position - Double(base)) * Double(Self.phases)).rounded())]
            let first = base - halfTaps + 1
            var l: Float = 0
            var r: Float = 0
            for tap in 0..<taps.count {
                l += left[first + tap] * taps[tap]
                r += right[first + tap] * taps[tap]
            }
            outLeft.append(l)
            outRight.append(r)
            position += step
        }
        // Drop input no later output can reach.
        let consumed = max(0, Int(position) - halfTaps + 1)
        if consumed > 0 {
            left.removeFirst(consumed)
            right.removeFirst(consumed)
            position -= Double(consumed)
        }
        return (outLeft, outRight)
    }
}
