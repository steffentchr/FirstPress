import Testing
import FirstPressCore

@Suite("Captured audio is stereo")
struct PCMBufferTests {
    @Test("A mono input plays on both sides")
    func monoIsDuplicated() {
        let buffer = PCMBuffer(inputID: "usb-deck", sampleRate: 44_100, time: 0, channels: [[0.1, -0.2, 0.3]])

        #expect(buffer.left == [0.1, -0.2, 0.3])
        #expect(buffer.right == [0.1, -0.2, 0.3])
    }

    @Test("A stereo input keeps its two sides")
    func stereoIsKept() {
        let buffer = PCMBuffer(inputID: "usb-deck", sampleRate: 48_000, time: 0, channels: [[0.1, 0.2], [0.3, 0.4]])

        #expect(buffer.left == [0.1, 0.2])
        #expect(buffer.right == [0.3, 0.4])
    }

    @Test("Channels beyond the first two are dropped")
    func extraChannelsDropped() {
        let buffer = PCMBuffer(inputID: "usb-deck", sampleRate: 48_000, time: 0, channels: [[0.1], [0.2], [0.9], [0.9]])

        #expect(buffer.left == [0.1])
        #expect(buffer.right == [0.2])
    }
}
