import Foundation

/// Port: the iPhone's own audio output (its speaker, earphones or an AirPlay
/// receiver) as an extra place a Record plays, alongside the Rooms.
///
/// The core decides when it plays; it hands over the captured audio as it
/// arrives, uncompressed, so it runs ahead of the Rooms. The volume is the
/// system's. The production adapter must never change which input is
/// captured: Bluetooth is only an output (A2DP), never a headset microphone.
@MainActor
public protocol PhoneOutput: AnyObject {
    /// The listener's switch, told at launch and whenever it changes, before
    /// `start()`. While it is off the adapter leaves the audio session exactly
    /// as capture alone sets it up.
    func switched(on: Bool)
    /// Starts playing: buffers handed over from now on are heard.
    func start()
    /// Captured audio to play now. Only handed over between `start()` and `stop()`.
    func play(_ buffer: PCMBuffer)
    /// Stops at once, dropping anything not yet heard.
    func stop()
}
