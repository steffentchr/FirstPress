import Foundation

/// The live MP3 stream Rooms play: ICY headers, then pre-roll, then live frames.
///
/// Every client gets the last ~3 s of frames as a burst first, so Sonos fills
/// its buffer at once and the first notes of a Record are not lost, then each
/// frame as the encoder produces it. Frames are whole, so every client starts
/// on a frame boundary.
///
/// A client that sends `Icy-MetaData: 1` also gets a metadata block after
/// every `metaint` bytes of audio, carrying the current title, so the Sonos
/// app shows what's playing.
@MainActor
final class StreamServer {
    /// How much audio a new client gets at once.
    static let preRollSeconds = 3.0
    static let preRollFrames = Int((preRollSeconds * MP3.sampleRate / Double(MP3.samplesPerFrame)).rounded(.up))
    /// Audio bytes between two metadata blocks: about 0.4 s at 320 kbps.
    nonisolated static let metaint = 16_384

    static let headers: [String: String] = [
        "Content-Type": "audio/mpeg",
        "icy-name": "First Press",
        "icy-br": "\(MP3.bitrate)",
        "icy-pub": "0",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Accept-Ranges": "none",
        "Connection": "close",
    ]

    /// Per client: whether it takes metadata, and how much audio it gets
    /// before the next block.
    private struct Client {
        var wantsMetadata: Bool
        var untilMetadata = StreamServer.metaint
    }

    private let sink: any StreamSink
    private let path: String
    private var preRoll: [Data] = []
    private var clients: [StreamClientID: Client] = [:]
    /// The block every client gets next, resent in full each time so a
    /// client that resyncs always has the title.
    private var metadataBlock = StreamServer.metadataBlock(for: "")

    /// What the Sonos app shows as the track: "Artist – Title", or empty
    /// while nothing is identified, which leaves just the station name.
    var title = "" {
        didSet { metadataBlock = Self.metadataBlock(for: title) }
    }

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
        for id in clients.keys {
            send(audio: bytes, to: id)
        }
    }

    private func handle(_ event: StreamSinkEvent) {
        switch event {
        case .connected(let id, let requestedPath, let wantsMetadata):
            guard requestedPath == path else {
                sink.close(id)
                return
            }
            var headers = Self.headers
            if wantsMetadata {
                headers["icy-metaint"] = "\(Self.metaint)"
            }
            sink.sendHeaders(headers, to: id)
            clients[id] = Client(wantsMetadata: wantsMetadata)
            let burst = preRoll.reduce(into: Data()) { $0.append($1) }
            send(audio: burst, to: id)
        case .disconnected(let id):
            clients[id] = nil
        }
    }

    /// Writes audio to one client, with a metadata block wherever its count
    /// of audio bytes reaches `metaint`.
    private func send(audio: Data, to id: StreamClientID) {
        guard !audio.isEmpty, var client = clients[id] else { return }
        guard client.wantsMetadata else {
            sink.send(audio, to: id)
            return
        }
        var out = Data()
        var index = audio.startIndex
        while index < audio.endIndex {
            let end = min(index + client.untilMetadata, audio.endIndex)
            out.append(audio[index..<end])
            client.untilMetadata -= end - index
            index = end
            if client.untilMetadata == 0 {
                out.append(metadataBlock)
                client.untilMetadata = Self.metaint
            }
        }
        clients[id] = client
        sink.send(out, to: id)
    }

    /// One length byte, then `StreamTitle='…';` in UTF-8 padded with zeros
    /// to a multiple of 16 bytes, at most 255 × 16.
    static func metadataBlock(for title: String) -> Data {
        // There is no escaping: a client takes `';` as the end of the title.
        // A typographic apostrophe reads the same and can't end it early.
        var clean = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .replacingOccurrences(of: "'", with: "’")
        let overhead = "StreamTitle='';".utf8.count
        let maxText = 255 * 16 - overhead
        while clean.utf8.count > maxText {
            clean.removeLast()
        }
        var text = Data("StreamTitle='\(clean)';".utf8)
        let units = (text.count + 15) / 16
        text.append(Data(count: units * 16 - text.count))
        return Data([UInt8(units)]) + text
    }
}
