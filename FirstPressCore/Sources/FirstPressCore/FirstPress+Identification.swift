import Foundation

/// What the Identifier finds: Now Playing, the stream's title and the
/// Plays kept in History.
extension FirstPress {
    func handle(_ event: Identifier.Event) {
        switch event {
        case .playStarted(var play):
            // Plays made while Last.fm isn't connected are never sent later.
            play.scrobble = isLastFmConnected ? .pending : .notScrobbled
            keep(play)
            keepCover(of: play.track)
            sessionLastTrack = play.track
            state.play = play
            stream.title = "\(play.track.artist) – \(play.track.title)"
            // A new Track wakes the screen and restarts the blank-after time.
            // While a Record plays the screen never blanks anyway, so this
            // matters only if that rule is ever relaxed.
            wakeScreen()
            scrobblePlayStarted(play)
        case .playEnded(let ended):
            // The Play as kept, with what Last.fm has added since it started.
            var play = history.first { $0.id == ended.id } ?? ended
            play.endedAt = ended.endedAt
            play.scrobble = scrobbleStatusAtEnd(of: play)
            keep(play)
            // Now Playing's Track fades out and Sonos shows just "First Press",
            // unless a new Play follows at once.
            state.play = nil
            stream.title = ""
        }
    }

    /// The Track's cover as kept on the phone: image data, nil if the Track
    /// has no artwork or its download hasn't succeeded yet.
    public func cover(for track: Track) -> Data? {
        track.artworkURL.flatMap { store.loadCover(for: $0) }
    }

    /// Downloads the cover unless it is already kept. A failed download is
    /// tried again the next time a Play of a Track with that artwork starts.
    private func keepCover(of track: Track) {
        guard let url = track.artworkURL, store.loadCover(for: url) == nil else { return }
        Task { [artwork, store] in
            guard let cover = try? await artwork.download(url) else { return }
            store.saveCover(cover, for: url)
        }
    }

    func loadHistory() {
        history = store.loadPlays().sorted { $0.startedAt > $1.startedAt }
    }

    /// Saves the Play, new or changed, and shows it in History. A Play is
    /// kept from its start, so one cut short by the app stopping isn't lost.
    func keep(_ play: Play) {
        store.savePlay(play)
        if let index = history.firstIndex(where: { $0.id == play.id }) {
            history[index] = play
        } else {
            let index = history.firstIndex { $0.startedAt <= play.startedAt } ?? history.endIndex
            history.insert(play, at: index)
        }
    }
}
