import Foundation
import Testing
import FirstPressCore

@Suite("Spotify search for a Play's Track")
struct SpotifySearchTests {
    @Test("The search is the artist and title, URL-encoded, on open.spotify.com")
    func artistAndTitle() {
        let track = Track(artist: "Kate Bush", title: "Wuthering Heights", album: "The Kick Inside")

        #expect(track.spotifySearchURL.absoluteString == "https://open.spotify.com/search/Kate%20Bush%20Wuthering%20Heights")
    }

    @Test("Slashes, ampersands, question marks and non-ASCII letters are encoded, not read as URL syntax")
    func reservedCharacters() {
        #expect(Track(artist: "AC/DC", title: "Rock & Roll?").spotifySearchURL.absoluteString
            == "https://open.spotify.com/search/AC%2FDC%20Rock%20%26%20Roll%3F")
        #expect(Track(artist: "Gasolin'", title: "Rabalderstræde").spotifySearchURL.absoluteString
            == "https://open.spotify.com/search/Gasolin%27%20Rabalderstr%C3%A6de")
    }
}
