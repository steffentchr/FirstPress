import Foundation
import FirstPressCore

extension FakeStreamSink {
    /// What a client received, read as its player would: as ICY when the
    /// response headers announced `icy-metaint`, as plain audio otherwise.
    @MainActor
    func icy(of client: StreamClientID) throws -> IcyClient {
        let body = received[client] ?? Data()
        guard let metaint = headers[client]?["icy-metaint"].flatMap(Int.init) else {
            return IcyClient(audio: body)
        }
        return try IcyClient(body, metaint: metaint)
    }

    /// The audio samples a client received, metadata taken out.
    @MainActor
    func audioSamples(of client: StreamClientID) throws -> [Float] {
        PassThroughEncoder.samples(in: try icy(of: client).audio)
    }
}

/// Reads a stream body the way a radio client that sent `Icy-MetaData: 1`
/// does: `metaint` bytes of audio, then one metadata block, again and again.
struct IcyClient {
    struct Malformed: Error, CustomStringConvertible {
        var description: String
    }

    /// The audio, with every metadata block taken out.
    var audio = Data()
    /// The text of each metadata block in order, nil for an empty block (a
    /// single zero length byte).
    var blocks: [String?] = []

    /// The StreamTitle of each non-empty block.
    var titles: [String] {
        blocks.compactMap { $0 }.map { block in
            guard block.hasPrefix("StreamTitle='"), block.hasSuffix("';") else { return "<\(block)>" }
            return String(block.dropFirst("StreamTitle='".count).dropLast(2))
        }
    }

    init(audio: Data) {
        self.audio = audio
    }

    init(_ body: Data, metaint: Int) throws {
        var index = body.startIndex
        while index < body.endIndex {
            let audioEnd = min(index + metaint, body.endIndex)
            audio.append(body[index..<audioEnd])
            let wasWhole = audioEnd - index == metaint
            index = audioEnd
            // A body that ends between blocks ends on audio.
            guard wasWhole, index < body.endIndex else { break }
            let length = Int(body[index]) * 16
            index += 1
            guard index + length <= body.endIndex else {
                throw Malformed(description: "metadata block runs past the end of the body")
            }
            if length == 0 {
                blocks.append(nil)
                continue
            }
            let block = body[index..<(index + length)]
            index += length
            guard let text = String(data: Data(block.reversed().drop { $0 == 0 }.reversed()), encoding: .utf8) else {
                throw Malformed(description: "metadata block is not UTF-8")
            }
            // Padding is zeros only, and less than one 16-byte unit.
            let padding = length - Data(text.utf8).count
            guard padding < 16 else { throw Malformed(description: "metadata block over-padded") }
            blocks.append(text)
        }
    }
}
