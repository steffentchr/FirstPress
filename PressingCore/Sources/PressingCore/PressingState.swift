import Foundation

/// The one snapshot the app renders. Later tickets add Session and Record
/// state, Rooms, the lower-third Track, the blanker and the Last.fm connection.
public struct PressingState: Sendable, Equatable {
    public var input: InputState

    public init(input: InputState = InputState()) {
        self.input = input
    }
}

public struct InputState: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// No input has been chosen in Settings yet.
        case notChosen
        /// The chosen input is not connected.
        case missing
        /// Capturing from the chosen input.
        case present
        /// Another app or a call has the audio session for now.
        case interrupted
        /// Microphone access has not been granted.
        case permissionDenied
        /// The chosen input runs at a rate Pressing does not take (only 44.1 and 48 kHz).
        case unsupportedSampleRate(Double)
        /// Capture could not start for another reason.
        case failed(String)
    }

    public var status: Status
    /// Inputs to offer in Settings.
    public var available: [AudioInputDevice]
    /// The input chosen in Settings.
    public var chosenID: AudioInputDevice.ID?
    /// Live level in dBFS, nil while nothing is being captured.
    public var level: Double?
    /// Level during silence (below the start threshold) in dBFS, nil until measured.
    public var noiseFloor: Double?

    public init(
        status: Status = .notChosen,
        available: [AudioInputDevice] = [],
        chosenID: AudioInputDevice.ID? = nil,
        level: Double? = nil,
        noiseFloor: Double? = nil
    ) {
        self.status = status
        self.available = available
        self.chosenID = chosenID
        self.level = level
        self.noiseFloor = noiseFloor
    }
}
