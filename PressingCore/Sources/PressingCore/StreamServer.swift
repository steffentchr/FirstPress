import Foundation

/// The live MP3 stream Rooms play: ICY headers, then pre-roll, then live frames.
///
/// Every client gets the last ~3 s of frames as a burst first, so Sonos fills
/// its buffer at once and the first notes of a side are not lost, then each
/// frame as the encoder produces it. Frames are whole, so every client starts
/// on a frame boundary.
@MainActor
final class StreamServer {
    /// How much audio a new client gets at once.
    static let preRollSeconds = 3.0
    static let preRollFrames = Int((preRollSeconds * MP3.sampleRate / Double(MP3.samplesPerFrame)).rounded(.up))

    static let headers: [String: String] = [
        "Content-Type": "audio/mpeg",
        "icy-name": "Pressing",
        "icy-br": "\(MP3.bitrate)",
        "icy-pub": "0",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Accept-Ranges": "none",
        "Connection": "close",
    ]

    private let sink: any StreamSink
    private let path: String
    private var preRoll: [Data] = []
    private var clients: Set<StreamClientID> = []

    init(sink: any StreamSink, path: String) {
        self.sink = sink
        self.path = path
    }

    func start(port: UInt16) {
        sink.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        // A port already in use leaves Rooms nothing to fetch; they show it
        // as a stream error in the Sonos app. Nothing in the core can fix it.
        try? sink.startListening(port: port)
    }

    /// Sends newly encoded frames to every client and keeps them for pre-roll.
    func send(_ frames: [Data]) {
        guard !frames.isEmpty else { return }
        preRoll += frames
        if preRoll.count > Self.preRollFrames {
            preRoll.removeFirst(preRoll.count - Self.preRollFrames)
        }
        let bytes = frames.reduce(into: Data()) { $0.append($1) }
        for client in clients {
            sink.send(bytes, to: client)
        }
    }

    private func handle(_ event: StreamSinkEvent) {
        switch event {
        case .connected(let client, let requestedPath, _):
            guard requestedPath == path else {
                sink.close(client)
                return
            }
            sink.sendHeaders(Self.headers, to: client)
            let burst = preRoll.reduce(into: Data()) { $0.append($1) }
            if !burst.isEmpty {
                sink.send(burst, to: client)
            }
            clients.insert(client)
        case .disconnected(let client):
            clients.remove(client)
        }
    }
}
