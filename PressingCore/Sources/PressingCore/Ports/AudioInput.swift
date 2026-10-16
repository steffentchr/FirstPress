import Foundation

/// An audio input the phone offers, such as the deck's USB output or the built-in mic.
public struct AudioInputDevice: Sendable, Hashable, Identifiable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case usb
        case builtInMic
        case other
    }

    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// What an AudioInput reports to the core.
public enum AudioInputEvent: Sendable {
    /// Captured audio from the input that was started.
    case buffer(PCMBuffer)
    /// The audio route changed: an input appeared or disappeared. The adapter has
    /// already stopped capture; the core decides whether to start it again.
    case routeChanged
    /// Another app or a call took the audio session.
    case interruptionBegan
    /// The interruption is over and capture may start again.
    case interruptionEnded
    /// The system's media services restarted; everything has to be set up again.
    case mediaServicesReset
}

public enum AudioInputError: Error, Sendable, Equatable {
    /// The listener has not granted microphone access.
    case permissionDenied
    /// The requested input is not connected, or the system routed elsewhere.
    case inputUnavailable
    /// Anything else the platform reported while starting capture.
    case failed(String)
}

/// Port: delivers captured audio from one explicitly chosen input.
///
/// The production adapter wraps `AVAudioSession` (`.record`, `.measurement`)
/// and selects the chosen input explicitly. It must never capture from any
/// input other than the one passed to `start(inputID:)`: when the route
/// changes it stops capture and reports `.routeChanged`, and the core decides
/// whether to start again.
@MainActor
public protocol AudioInput: AnyObject {
    /// The inputs available right now.
    var availableInputs: [AudioInputDevice] { get }

    /// Where events go. Set once by the core.
    func setEventHandler(_ handler: @escaping @MainActor (AudioInputEvent) -> Void)

    /// Starts (or restarts) capture from exactly this input.
    func start(inputID: AudioInputDevice.ID) throws

    /// Stops capture.
    func stop()
}
