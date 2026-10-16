import Foundation
import PressingCore

/// In-memory Store. Share one between two cores to simulate a restart.
@MainActor
final class FakeStore: Store {
    var settings: Settings?

    init(settings: Settings? = nil) {
        self.settings = settings
    }

    func loadSettings() -> Settings? { settings }
    func saveSettings(_ settings: Settings) { self.settings = settings }

    /// Plays, in the order they were first saved.
    private(set) var plays: [Play] = []
    func savePlay(_ play: Play) {
        if let index = plays.firstIndex(where: { $0.id == play.id }) {
            plays[index] = play
        } else {
            plays.append(play)
        }
    }
    func loadPlays() -> [Play] { plays }

    private(set) var covers: [URL: Data] = [:]
    func saveCover(_ cover: Data, for artworkURL: URL) { covers[artworkURL] = cover }
    func loadCover(for artworkURL: URL) -> Data? { covers[artworkURL] }
    /// Plays that have ended, in the order they were saved.
    var endedPlays: [Play] { plays.filter { $0.endedAt != nil } }
}
