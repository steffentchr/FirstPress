import Foundation

/// Port: the MP3 encoder (ADR-0002).
///
/// Takes 44.1 kHz stereo float PCM in the ±1.0 range and returns whole MPEG-1
/// Layer III frames, each holding `MP3.samplesPerFrame` samples per channel.
/// The core resamples to 44.1 kHz first and does the stream framing and
/// pre-roll, so a new client always starts on a frame boundary.
///
/// Production: LAME 3.100 at 320 kbps CBR. Tests use a pass-through fake.
@MainActor
public protocol MP3Encoder: AnyObject {
    /// Encodes the next stretch of audio. Returns the frames it completed,
    /// which may be none; the rest is held until the next call.
    func encode(left: [Float], right: [Float]) -> [Data]
}

public enum MP3 {
    /// The rate Pressing streams at, whatever rate the input offers.
    public static let sampleRate = 44_100.0
    /// Samples per channel in one MPEG-1 Layer III frame.
    public static let samplesPerFrame = 1152
    /// The stream's constant bitrate, in kbps.
    public static let bitrate = 320
}
