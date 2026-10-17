import Foundation
import Testing
import FirstPressCore

@MainActor
@Suite("The stream")
struct StreamTests {
    private let rate = 44_100.0
    private let sonos = StreamClientID(1)

    /// A ramp: sample i is i, so the samples a client gets show exactly which
    /// stretch of the deck's audio they came from.
    private func ramp(from start: Int, seconds: Double) -> [Float] {
        (start..<(start + Int(seconds * rate))).map(Float.init)
    }

    @Test("The stream listens on a fixed port and path")
    func fixedPortAndPath() {
        let world = World()

        #expect(world.sink.listeningPort == FirstPress.streamPort)
        #expect(FirstPress.streamPath.hasPrefix("/"))
    }

    @Test("A new client gets ICY headers naming First Press, then about 3 s of pre-roll")
    func preRoll() throws {
        let world = World()
        world.play(ramp(from: 0, seconds: 5))

        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)

        let headers = try #require(world.sink.headers[sonos])
        #expect(headers["icy-name"] == "First Press")
        #expect(headers["Content-Type"] == "audio/mpeg")
        let samples = try world.sink.audioSamples(of: sonos)
        let seconds = Double(samples.count) / rate
        #expect(seconds >= 2.9 && seconds <= 3.1)
        // The pre-roll is the newest audio, whole frames, in order.
        let newestFramed = Float(5 * 44_100 / MP3.samplesPerFrame * MP3.samplesPerFrame - 1)
        #expect(samples.last == newestFramed)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1 == $0 + 1 })
    }

    @Test("After the pre-roll, a client gets the live audio as it is encoded")
    func live() throws {
        let world = World()
        world.play(ramp(from: 0, seconds: 5))
        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: false)

        world.play(ramp(from: 5 * 44_100, seconds: 2))

        let samples = try world.sink.audioSamples(of: sonos)
        #expect(samples.last == Float(7 * 44_100 / MP3.samplesPerFrame * MP3.samplesPerFrame - 1))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1 == $0 + 1 })
    }

    @Test("Two clients each get the pre-roll and the live audio")
    func twoClients() throws {
        let world = World()
        let other = StreamClientID(2)
        world.play(ramp(from: 0, seconds: 4))
        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: true)
        world.play(ramp(from: 4 * 44_100, seconds: 1))

        world.sink.connect(other, path: FirstPress.streamPath, wantsMetadata: true)
        world.play(ramp(from: 5 * 44_100, seconds: 1))

        let first = try world.sink.audioSamples(of: sonos)
        let second = try world.sink.audioSamples(of: other)
        #expect(first.last == second.last)
        #expect(Double(first.count) / rate > 3.9)
        #expect(Double(second.count) / rate > 3.9 && Double(second.count) / rate < 4.1)
    }

    @Test("A request for any other path is closed without audio")
    func wrongPath() {
        let world = World()
        world.play(ramp(from: 0, seconds: 4))

        world.sink.connect(sonos, path: "/favicon.ico", wantsMetadata: false)
        world.play(ramp(from: 4 * 44_100, seconds: 1))

        #expect(world.sink.closed.contains(sonos))
        #expect(world.sink.received[sonos] == nil)
    }

    @Test("A disconnected client gets nothing more")
    func disconnect() {
        let world = World()
        world.play(ramp(from: 0, seconds: 4))
        world.sink.connect(sonos, path: FirstPress.streamPath, wantsMetadata: false)
        let before = world.sink.received[sonos]

        world.sink.disconnect(sonos)
        world.play(ramp(from: 4 * 44_100, seconds: 1))

        #expect(world.sink.received[sonos] == before)
    }

    @Test("A 48 kHz deck is resampled to a 44.1 kHz stream")
    func resampled() {
        let world = World()
        let input = 48_000.0
        // A 1 kHz sine: 2,000 zero crossings per second at any sample rate.
        let sine = (0..<Int(3 * input)).map { Float(0.5 * sin(2 * Double.pi * 1_000 * Double($0) / input)) }

        world.play(sine, sampleRate: input)

        let streamed = world.encoder.received
        #expect(abs(Double(streamed.count) - 3 * rate) < 100)
        // One second from the middle, taken as 44,100 samples.
        let second = Array(streamed[Int(rate)..<Int(2 * rate)])
        let crossings = zip(second, second.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        #expect(abs(crossings - 2_000) <= 2)
        #expect(abs(Double(second.max() ?? 0) - 0.5) < 0.01)
    }
}
