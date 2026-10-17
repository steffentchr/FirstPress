import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("Stream titles")
struct StreamTitleTests {
    private let rate = 44_100.0
    private let sonos = StreamClientID(1)

    private func ramp(from start: Int, seconds: Double) -> [Float] {
        (start..<(start + Int(seconds * rate))).map { Float($0) / 1_000_000 }
    }

    @Test("Only a client that sends Icy-MetaData: 1 is told icy-metaint")
    func metaintOnlyWhenAsked() throws {
        let world = World()
        let plain = StreamClientID(2)

        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)
        world.sink.connect(plain, path: FirstPress.streamPath, wantsMetadata: false)

        #expect(world.sink.headers[sonos]?["icy-metaint"] == "16384")
        #expect(world.sink.headers[plain]?["icy-metaint"] == nil)
        #expect(world.sink.headers[plain]?["icy-name"] == "First Press")
    }

    @Test("A metadata block comes after exactly every icy-metaint bytes of audio, with an empty title while nothing is identified")
    func blocksEveryMetaint() throws {
        let world = World()
        world.play(ramp(from: 0, seconds: 4))
        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)

        world.play(ramp(from: 4 * 44_100, seconds: 3))

        let icy = try world.sink.icy(of: sonos)
        let samples = PassThroughEncoder.samples(in: icy.audio)
        // Cutting the body at any other place would tear samples apart.
        #expect(zip(samples, samples.dropFirst()).allSatisfy { abs($1 - $0 - 1 / 1_000_000) < 1e-7 })
        #expect(icy.blocks.count == icy.audio.count / 16_384)
        #expect(icy.blocks.count > 10)
        #expect(icy.titles.allSatisfy { $0 == "" })
    }

    @Test("A block carrying a title is a length byte, StreamTitle='Artist – Title'; in UTF-8 and zero padding")
    func blockBytes() async throws {
        let world = World()
        world.recognizer.answers = [.match(Track(artist: "Artist", title: "Title"), offset: 30)]
        world.music(seconds: 12)
        await settle()

        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)
        let body = try #require(world.sink.received[sonos])

        // The worked example from the ICY notes: 0x02, 31 bytes of text, one 0x00.
        let expected: [UInt8] = [
            0x02, 0x53, 0x74, 0x72, 0x65, 0x61, 0x6D, 0x54, 0x69, 0x74, 0x6C, 0x65, 0x3D, 0x27, 0x41, 0x72, 0x74,
            0x69, 0x73, 0x74, 0x20, 0xE2, 0x80, 0x93, 0x20, 0x54, 0x69, 0x74, 0x6C, 0x65, 0x27, 0x3B, 0x00,
        ]
        #expect(Array(body[16_384..<(16_384 + expected.count)]) == expected)
    }

    @Test("Once a Track is identified the blocks carry it, and a Flip empties the title again")
    func titleFollowsPlay() async throws {
        let world = World()
        world.recognizer.answers = [.match(.ballad, offset: 30)]
        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)

        world.music(seconds: 12)
        await settle()
        world.music(seconds: 2)
        world.silence(seconds: 15)

        let titles = try world.sink.icy(of: sonos).titles
        #expect(titles.first == "")
        #expect(titles.contains("Kate Bush – Wuthering Heights"))
        #expect(titles.last == "")
        // In that order: empty, the Track, empty.
        let changes = titles.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        #expect(changes == ["", "Kate Bush – Wuthering Heights", ""])
    }

    @Test("An apostrophe in a title can't end the StreamTitle early")
    func apostrophe() async throws {
        let world = World()
        world.recognizer.answers = [.match(.rocker, offset: 30)]
        world.music(seconds: 12)
        await settle()

        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)

        let titles = try world.sink.icy(of: sonos).titles
        #expect(titles.first == "Gasolin’ – Rabalderstræde")
    }
}
