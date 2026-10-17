// App Store screenshot hook. AppStore/FirstPress/screenshots.sh copies this into
// App/Sources for one run and removes it again; it is never committed there.
// It wires First Press to the test fakes and plays AppStore/FirstPress/demo.json.
import Foundation
import FirstPressCore

@MainActor
enum ScreenshotDemo {
    static var scene: String? { UserDefaults.standard.string(forKey: "FirstPressScreenshot") }
    private static var keep: [AnyObject] = []
    private static var timer: Timer?

    private struct Demo: Decodable {
        struct Room: Decodable { var name: String; var on: Bool; var volume: Int }
        struct Item: Decodable { var title: String; var artist: String; var album: String; var cover: String; var minutesAgo: Double?; var seconds: Int? }
        var input: String
        var lastFmUsername: String
        var rooms: [Room]
        var nowPlaying: Item
        var history: [Item]
    }

    private static func track(_ item: Demo.Item) -> Track {
        Track(artist: item.artist, title: item.title, album: item.album,
              artworkURL: Bundle.main.url(forResource: item.cover, withExtension: "png", subdirectory: "ScreenshotDemo"))
    }

    static func makeFirstPress() -> FirstPress {
        let url = Bundle.main.url(forResource: "demo", withExtension: "json", subdirectory: "ScreenshotDemo")!
        let demo = try! JSONDecoder().decode(Demo.self, from: Data(contentsOf: url))

        let deck = AudioInputDevice(id: "usb-audio", name: demo.input, kind: .usb)
        let input = FakeAudioInput(availableInputs: [deck])
        let rooms = demo.rooms.enumerated().map { index, room in
            FakeRoom(uuid: String(format: "RINCON_000E58%06d01400", index), name: room.name, host: "192.168.1.\(101 + index)")
        }
        let sonos = FakeSonos(groups: rooms.map { [$0] })
        var choices: [String: RoomChoice] = [:]
        for (fake, room) in zip(rooms, demo.rooms) { choices[fake.uuid] = RoomChoice(isOn: room.on, volume: room.volume) }
        let store = FakeStore(settings: Settings(inputID: deck.id, inputName: deck.name, rooms: choices))

        let now = Date()
        for item in demo.history {
            let track = track(item)
            let start = now.addingTimeInterval(-(item.minutesAgo ?? 0) * 60)
            store.savePlay(Play(track: track, startedAt: start, endedAt: start.addingTimeInterval(200), scrobble: .scrobbled))
            store.saveCover(try! Data(contentsOf: track.artworkURL!), for: track.artworkURL!)
        }
        let current = track(demo.nowPlaying)
        let recognizer = FakeRecognizer()
        recognizer.answers = Array(repeating: .match(current, offset: 40), count: 50)
        let artwork = FakeArtworkDownloader()
        artwork.covers[current.artworkURL!] = try! Data(contentsOf: current.artworkURL!)
        let lastFm = FakeLastFm()
        lastFm.knows(current, durationMilliseconds: (demo.nowPlaying.seconds ?? 240) * 1000, album: current.album)

        let firstPress = FirstPress(
            audioInput: input, store: store, scheduler: MainQueueScheduler(),
            sonos: sonos.network, streamSink: FakeStreamSink(), encoder: PassThroughEncoder(),
            phoneOutput: FakePhoneOutput(), recognizer: recognizer, artwork: artwork,
            lastFm: LastFmPorts(account: .test, http: lastFm, webAuth: FakeWebAuth(),
                                keychain: FakeKeychain(session: LastFmSession(username: demo.lastFmUsername, key: "K"))),
            menuServer: SilentMenuServer()
        )
        keep = [input, sonos, store, recognizer, artwork, lastFm]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for room in rooms { sonos.discover(room) }
        }
        // The waiting and settings scenes show the start screen, so no Record plays.
        if scene != "waiting" && scene != "settings" {
            var time = 0.0
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let frames = 2205
                    let music = (0..<frames).map { $0 % 2 == 0 ? Float(0.1) : -0.1 }
                    input.send(.buffer(PCMBuffer(inputID: deck.id, sampleRate: 44_100, time: time, channels: [music])))
                    time += Double(frames) / 44_100
                }
            }
        }
        return firstPress
    }
}

/// No First Press Menu on the Mac: the screenshots don't show one.
@MainActor
private final class SilentMenuServer: MenuServer {
    func setEventHandler(_ handler: @escaping @MainActor (MenuServerEvent) -> Void) {}
    func start() {}
    func stop() {}
    func send(_ message: Data, to connection: MenuConnectionID) {}
}
