import Foundation
import LAME
import FirstPressCore

/// Production MP3Encoder: LAME 3.100 at 320 kbps CBR, 44.1 kHz joint stereo
/// (ADR-0002). LAME's output isn't aligned to calls, so it is split on MPEG
/// frame headers and only whole frames are returned.
///
/// Built by scripts/build-lame.sh. One handle, used on the main actor only:
/// LAME isn't thread-safe per handle.
@MainActor
final class LAMEEncoder: MP3Encoder {
    private let lame: lame_t
    private var output: [UInt8] = []
    private var pending: [UInt8] = []

    init() {
        guard let lame = lame_init() else { fatalError("lame_init failed") }
        lame_set_num_channels(lame, 2)
        lame_set_in_samplerate(lame, Int32(MP3.sampleRate))
        lame_set_out_samplerate(lame, Int32(MP3.sampleRate))
        lame_set_VBR(lame, vbr_off)
        lame_set_brate(lame, Int32(MP3.bitrate))
        lame_set_mode(lame, JOINT_STEREO)
        lame_set_quality(lame, 2)
        // No Xing/Info frame: meaningless for an endless stream.
        lame_set_bWriteVbrTag(lame, 0)
        guard lame_init_params(lame) >= 0 else { fatalError("lame_init_params failed") }
        self.lame = lame
    }

    func encode(left: [Float], right: [Float]) -> [Data] {
        let count = min(left.count, right.count)
        guard count > 0 else { return [] }
        // Worst case from lame.h: 1.25 × samples + 7200.
        let needed = count + count / 4 + 7_200
        if output.count < needed {
            output = [UInt8](repeating: 0, count: needed)
        }
        let written = output.withUnsafeMutableBufferPointer { buffer in
            lame_encode_buffer_ieee_float(lame, left, right, Int32(count), buffer.baseAddress, Int32(buffer.count))
        }
        guard written > 0 else { return [] }
        pending.append(contentsOf: output[0..<Int(written)])
        return splitFrames()
    }

    /// Takes whole MPEG-1 Layer III frames off the front of `pending`.
    private func splitFrames() -> [Data] {
        var frames: [Data] = []
        var start = 0
        while pending.count - start >= 4 {
            guard let size = Self.frameSize(pending[start], pending[start + 1], pending[start + 2]) else {
                // Not a frame header: skip to the next sync byte.
                start += 1
                continue
            }
            guard pending.count - start >= size else { break }
            frames.append(Data(pending[start..<(start + size)]))
            start += size
        }
        pending.removeFirst(start)
        return frames
    }

    private static let bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    private static let sampleRates = [44_100, 48_000, 32_000]

    /// The byte length of the MPEG-1 Layer III frame whose header starts with these bytes.
    private static func frameSize(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Int? {
        // 11 sync bits, MPEG-1 (11), Layer III (01).
        guard b0 == 0xFF, b1 & 0xFE == 0xFA else { return nil }
        let bitrateIndex = Int(b2 >> 4)
        let rateIndex = Int((b2 >> 2) & 0x03)
        guard bitrateIndex > 0, bitrateIndex < bitrates.count, rateIndex < sampleRates.count else { return nil }
        let padding = Int((b2 >> 1) & 0x01)
        return 144 * bitrates[bitrateIndex] * 1_000 / sampleRates[rateIndex] + padding
    }
}
