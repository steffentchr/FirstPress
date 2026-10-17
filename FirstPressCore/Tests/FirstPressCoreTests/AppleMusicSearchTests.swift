import Foundation
import Testing
import FirstPressCore
import FirstPressMenuCore

@Suite("Apple Music search for a Track")
struct AppleMusicSearchTests {
    @Test("The search is the artist and title, URL-encoded, on music.apple.com")
    func artistAndTitle() {
        let track = Track(artist: "Kate Bush", title: "Wuthering Heights", album: "The Kick Inside")

        #expect(track.appleMusicSearchURL.absoluteString == "https://music.apple.com/search?term=Kate%20Bush%20Wuthering%20Heights")
    }

    @Test("Slashes, ampersands, question marks and non-ASCII letters are encoded, not read as URL syntax")
    func reservedCharacters() {
        #expect(Track(artist: "AC/DC", title: "Rock & Roll?").appleMusicSearchURL.absoluteString
            == "https://music.apple.com/search?term=AC%2FDC%20Rock%20%26%20Roll%3F")
        #expect(Track(artist: "Gasolin'", title: "Rabalderstræde").appleMusicSearchURL.absoluteString
            == "https://music.apple.com/search?term=Gasolin%27%20Rabalderstr%C3%A6de")
    }
}

@Suite("Find songs in")
struct FindTracksInTests {
    @Test("First Press Menu searches the service chosen in Settings, Spotify by default")
    func chosenService() {
        let track = Track(artist: "Kate Bush", title: "Wuthering Heights")

        #expect(TrackSearchService.default == .spotify)
        #expect(TrackSearchService.spotify.searchURL(for: track).absoluteString == "https://open.spotify.com/search/Kate%20Bush%20Wuthering%20Heights")
        #expect(TrackSearchService.appleMusic.searchURL(for: track).absoluteString == "https://music.apple.com/search?term=Kate%20Bush%20Wuthering%20Heights")
    }
}
