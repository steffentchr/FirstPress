import Foundation

/// What the Identifier finds: the lower third, the stream's title and the
/// stored Plays.
extension Pressing {
    func handle(_ event: Identifier.Event) {
        switch event {
        case .playStarted(let play):
            state.play = play
            stream.title = "\(play.track.artist) – \(play.track.title)"
            // A new Track wakes the screen and restarts the blank-after time.
            // While a Record plays the screen never blanks anyway, so this
            // matters only if that rule is ever relaxed.
            wakeScreen()
        case .playEnded(let play):
            store.savePlay(play)
            // The lower third fades out and Sonos shows just "Pressing",
            // unless a new Play follows at once.
            state.play = nil
            stream.title = ""
        }
    }
}
