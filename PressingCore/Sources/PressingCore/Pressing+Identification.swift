import Foundation

/// What the Identifier finds: the lower third, the stream's title and the
/// Plays kept in History.
extension Pressing {
    func handle(_ event: Identifier.Event) {
        switch event {
        case .playStarted(let play):
            keep(play)
            state.play = play
            stream.title = "\(play.track.artist) – \(play.track.title)"
            // A new Track wakes the screen and restarts the blank-after time.
            // While a Record plays the screen never blanks anyway, so this
            // matters only if that rule is ever relaxed.
            wakeScreen()
        case .playEnded(let play):
            keep(play)
            // The lower third fades out and Sonos shows just "Pressing",
            // unless a new Play follows at once.
            state.play = nil
            stream.title = ""
        }
    }

    func loadHistory() {
        history = store.loadPlays().sorted { $0.startedAt > $1.startedAt }
    }

    /// Saves the Play, new or changed, and shows it in History. A Play is
    /// kept from its start, so one cut short by the app stopping isn't lost.
    private func keep(_ play: Play) {
        store.savePlay(play)
        if let index = history.firstIndex(where: { $0.id == play.id }) {
            history[index] = play
        } else {
            let index = history.firstIndex { $0.startedAt <= play.startedAt } ?? history.endIndex
            history.insert(play, at: index)
        }
    }
}
