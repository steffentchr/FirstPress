import AVFAudio
import Foundation
import FirstPressCore
import ShazamKit

/// Production Recognizer: one ShazamKit search per call, against the Shazam
/// catalog, with a fresh `SHSession` and `SHSignatureGenerator` each time.
///
/// `SHManagedSession` is not usable here: it records audio itself, and
/// First Press already owns the capture on the deck's input. Matching the Shazam
/// catalog needs the ShazamKit App Service on the App ID (see README).
@MainActor
final class ShazamRecognizer: Recognizer {
    struct Unavailable: Error {
        var underlying: any Error
    }

    func recognize(_ samples: [Float], sampleRate: Double) async throws -> Recognition {
        let session = SHSession()
        // The catalog refuses signatures outside its limits; keep the newest audio.
        let maxFrames = Int(session.catalog.maximumQuerySignatureDuration * sampleRate)
        let audio = maxFrames > 0 && samples.count > maxFrames ? Array(samples.suffix(maxFrames)) : samples

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)),
              let channel = buffer.floatChannelData?[0]
        else { return .noMatch }
        buffer.frameLength = AVAudioFrameCount(audio.count)
        audio.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: audio.count)
        }

        let generator = SHSignatureGenerator()
        do {
            try generator.append(buffer, at: AVAudioTime(sampleTime: 0, atRate: sampleRate))
        } catch {
            return .noMatch
        }
        let signature = generator.signature()

        switch await session.result(from: signature) {
        case .match(let match):
            guard let item = match.mediaItems.first else { return .noMatch }
            let track = Track(
                artist: item.artist ?? "",
                title: item.title ?? "",
                // ShazamKit has no album; it comes from Last.fm later.
                album: nil,
                artworkURL: item.artworkURL
            )
            // `matchOffset` is where the signature's start falls in the Track.
            // The port wants where the audio handed in starts, so add back
            // any audio trimmed off its front.
            let trimmed = Double(samples.count - audio.count) / sampleRate
            return .match(track, offset: item.matchOffset - trimmed)
        case .noMatch:
            return .noMatch
        case .error(let error, _):
            // Shazam's servers couldn't answer: neither a match nor a miss.
            // Anything else (silence, a bad signature) is a miss.
            if let shError = error as? SHError, shError.code == .matchAttemptFailed {
                throw Unavailable(underlying: error)
            }
            if (error as NSError).domain == NSURLErrorDomain {
                throw Unavailable(underlying: error)
            }
            return .noMatch
        @unknown default:
            return .noMatch
        }
    }
}
