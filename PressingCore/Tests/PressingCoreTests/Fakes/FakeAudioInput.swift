import Foundation
import PressingCore

/// AudioInput fake: the test plugs inputs in and out and feeds audio.
@MainActor
final class FakeAudioInput: AudioInput {
    var availableInputs: [AudioInputDevice]
    /// Every `start(inputID:)` call, in order.
    private(set) var startedInputs: [AudioInputDevice.ID] = []
    private(set) var stopCount = 0
    /// What the next `start` throws, if anything.
    var startError: AudioInputError?
    private var handler: (@MainActor (AudioInputEvent) -> Void)?

    init(availableInputs: [AudioInputDevice] = []) {
        self.availableInputs = availableInputs
    }

    func setEventHandler(_ handler: @escaping @MainActor (AudioInputEvent) -> Void) {
        self.handler = handler
    }

    func start(inputID: AudioInputDevice.ID) throws {
        startedInputs.append(inputID)
        if let startError { throw startError }
    }

    func stop() {
        stopCount += 1
    }

    // MARK: Test controls

    func plugIn(_ device: AudioInputDevice) {
        availableInputs.append(device)
        handler?(.routeChanged)
    }

    func unplug(_ id: AudioInputDevice.ID) {
        availableInputs.removeAll { $0.id == id }
        handler?(.routeChanged)
    }

    func send(_ event: AudioInputEvent) {
        handler?(event)
    }
}

extension AudioInputDevice {
    static let deck = AudioInputDevice(id: "usb-deck", name: "Numark TT USB", kind: .usb)
    static let mic = AudioInputDevice(id: "built-in-mic", name: "iPhone Microphone", kind: .builtInMic)
}
