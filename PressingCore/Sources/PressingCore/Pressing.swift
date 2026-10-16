import Foundation
import Observation

/// The headless core. The app renders `state` and forwards intents.
@MainActor
@Observable
public final class Pressing {
    public private(set) var state = PressingState()

    @ObservationIgnored private let audioInput: any AudioInput
    @ObservationIgnored private let store: any Store

    public init(audioInput: any AudioInput, store: any Store) {
        self.audioInput = audioInput
        self.store = store
    }

    /// Call once at launch.
    public func start() {
        settings = store.loadSettings() ?? Settings()
        state.input.chosenID = settings.inputID
        state.input.available = audioInput.availableInputs
        audioInput.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        startCapture()
    }

    private func handle(_ event: AudioInputEvent) {
        switch event {
        case .buffer:
            break
        case .routeChanged:
            state.input.available = audioInput.availableInputs
            startCapture()
        case .interruptionBegan:
            state.input.status = .interrupted
        case .interruptionEnded, .mediaServicesReset:
            startCapture()
        }
    }

    /// Intent from Settings: capture from this input from now on.
    public func chooseInput(_ id: AudioInputDevice.ID) {
        settings.inputID = id
        store.saveSettings(settings)
        state.input.chosenID = id
        startCapture()
    }

    @ObservationIgnored private var settings = Settings()

    private func startCapture() {
        guard let chosen = settings.inputID else {
            state.input.status = .notChosen
            return
        }
        // Never fall back: if the chosen input isn't there, capture nothing.
        guard state.input.available.contains(where: { $0.id == chosen }) else {
            audioInput.stop()
            state.input.status = .missing
            return
        }
        do {
            try audioInput.start(inputID: chosen)
            state.input.status = .present
        } catch AudioInputError.permissionDenied {
            state.input.status = .permissionDenied
        } catch AudioInputError.inputUnavailable {
            state.input.status = .missing
        } catch AudioInputError.failed(let reason) {
            state.input.status = .failed(reason)
        } catch {
            state.input.status = .failed("\(error)")
        }
    }
}
