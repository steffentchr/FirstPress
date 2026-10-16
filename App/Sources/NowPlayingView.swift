import SwiftUI
import PressingCore

/// Shown while a Session runs: the current Track, large enough to read from
/// across the room, and nothing else.
///
/// The Track's space is always reserved and only its opacity changes, so
/// nothing moves between Tracks, after a Flip or for an unknown Record. When
/// a Play ends with no successor the last Track stays drawn while it fades out.
struct NowPlayingView: View {
    let play: Play?

    /// The Track being shown or fading out.
    @State private var shown: Track?

    var body: some View {
        VStack(spacing: 24) {
            AsyncImage(url: shown?.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 6) {
                Text(shown?.title ?? " ")
                    .font(.largeTitle.bold())
                Text(shown?.artist ?? " ")
                    .font(.title2)
                Text(shown?.album ?? " ")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding()
        .opacity(play == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.8), value: play == nil)
        .onChange(of: play?.track, initial: true) { _, track in
            // Keep the old Track drawn while fading out; swap in a new one at once.
            if let track { shown = track }
        }
        .accessibilityElement(children: .combine)
    }
}
