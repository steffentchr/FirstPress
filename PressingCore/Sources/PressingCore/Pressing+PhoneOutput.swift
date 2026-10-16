import Foundation

/// The Phone output follows the Session, like a Room: while it is switched
/// on, the Record plays on the phone from Record start until the Session
/// ends, Gaps and Flips included.
extension Pressing {
    /// Intent from the Rooms sheet: switch "This iPhone" on or off.
    public func switchPhoneOutput(on: Bool) {
        settings.phoneOutput = on
        store.saveSettings(settings)
        applyPhoneOutputSwitch()
    }

    /// Tells the phone the switch as set. At launch this comes before capture
    /// starts, so the audio session is set up for it from the first start.
    func applyPhoneOutputSwitch() {
        state.phoneOutput.isOn = settings.phoneOutput
        phoneOutput.switched(on: settings.phoneOutput)
        updatePhoneOutput()
    }

    /// Starts or stops the Phone output to match the switch and the Session.
    func updatePhoneOutput() {
        let shouldPlay = settings.phoneOutput && state.session != .idle
        guard shouldPlay != isPhoneOutputPlaying else { return }
        isPhoneOutputPlaying = shouldPlay
        if shouldPlay {
            phoneOutput.start()
        } else {
            phoneOutput.stop()
        }
    }

    /// Hands captured audio to the Phone output while it plays.
    func playOnPhone(_ buffer: PCMBuffer) {
        guard isPhoneOutputPlaying else { return }
        phoneOutput.play(buffer)
    }
}
