import Foundation
import FirstPressCore
import FirstPressMenuCore

extension FirstPress {
    /// For tests that only care about the input: every other port is a fake
    /// nobody looks at.
    convenience init(audioInput: any AudioInput, store: any Store, scheduler: any Scheduler) {
        self.init(
            audioInput: audioInput,
            store: store,
            scheduler: scheduler,
            sonos: FakeSonosNetwork(),
            streamSink: FakeStreamSink(),
            encoder: PassThroughEncoder(),
            phoneOutput: FakePhoneOutput(),
            recognizer: FakeRecognizer(),
            artwork: FakeArtworkDownloader(),
            lastFm: LastFmPorts(account: .test, http: FakeLastFm(), webAuth: FakeWebAuth(), keychain: FakeKeychain()),
            menuServer: FakeMenuServer()
        )
    }
}

/// First Press wired to a fake of every port, with the deck chosen and plugged in.
@MainActor
struct World {
    let input = FakeAudioInput(availableInputs: [.deck])
    let scheduler = FakeScheduler()
    let store: FakeStore
    let sonos: FakeSonos
    let sink = FakeStreamSink()
    let encoder = PassThroughEncoder()
    let phoneOutput = FakePhoneOutput()
    let recognizer = FakeRecognizer()
    let artwork = FakeArtworkDownloader()
    let lastFm = FakeLastFm()
    let webAuth = FakeWebAuth()
    let keychain: FakeKeychain
    let menuServer = FakeMenuServer()
    let firstPress: FirstPress

    /// `lastFm` is the session in the Keychain at launch: by default Last.fm
    /// isn't connected. A nil `account` is a build without an API key.
    /// `answering` replaces Last.fm's answers before launch.
    init(
        settings: Settings = Settings(inputID: AudioInputDevice.deck.id),
        sonos: FakeSonos = FakeSonos(),
        store: FakeStore? = nil,
        account: LastFmAccount? = .test,
        lastFm session: LastFmSession? = nil,
        keychain: FakeKeychain? = nil,
        answering answers: [String: @MainActor (LastFmCall) -> HTTPResponse] = [:]
    ) {
        self.store = store ?? FakeStore(settings: settings)
        self.keychain = keychain ?? FakeKeychain(session: session)
        self.sonos = sonos
        lastFm.answers.merge(answers) { $1 }
        firstPress = FirstPress(
            audioInput: input,
            store: self.store,
            scheduler: scheduler,
            sonos: sonos.network,
            streamSink: sink,
            encoder: encoder,
            phoneOutput: phoneOutput,
            recognizer: recognizer,
            artwork: artwork,
            lastFm: LastFmPorts(account: account, http: lastFm, webAuth: webAuth, keychain: self.keychain),
            menuServer: menuServer
        )
        firstPress.start()
    }

    /// A First Press Menu on a Mac on the same network, joined to this phone by
    /// an in-memory link. It starts looking for First Press at once, unless
    /// macOS hasn't allowed it on the local network (`localNetworkDenied`).
    func firstPressMenu(localNetworkDenied: Bool = false) -> (menu: FirstPressMenu, link: FakeMenuLink) {
        let link = FakeMenuLink(server: menuServer)
        link.isLocalNetworkDenied = localNetworkDenied
        let menu = FirstPressMenu(link: link, scheduler: scheduler)
        menu.start()
        return (menu, link)
    }

    /// Plays mono samples from the deck in real time.
    func play(_ samples: [Float], sampleRate: Double = 44_100) {
        input.play(samples, sampleRate: sampleRate, on: scheduler)
    }

    /// Music, well above the default threshold.
    func music(seconds: Double, sampleRate: Double = 44_100) {
        play(Signal.square(amplitude: 0.1, seconds: seconds, sampleRate: sampleRate), sampleRate: sampleRate)
    }

    /// Silence, below the default threshold.
    func silence(seconds: Double) {
        play(Signal.square(amplitude: 0.001, seconds: seconds, sampleRate: 44_100))
    }
}
