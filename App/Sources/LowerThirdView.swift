import SwiftUI
import PressingCore

/// Artist, title, album and cover of the current Play, in a fixed area at the
/// bottom of the main screen, readable from across the room.
///
/// The area is always reserved and only its opacity changes, so nothing in
/// the layout moves. When a Play ends with no successor the last Track stays
/// drawn while it fades out.
struct LowerThirdView: View {
    let play: Play?

    static let height: CGFloat = 132
    private static let cover: CGFloat = 116

    /// The Track being shown or fading out.
    @State private var shown: Track?

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: shown?.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: Self.cover, height: Self.cover)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(shown?.title ?? " ")
                    .font(.title.bold())
                Text(shown?.artist ?? " ")
                    .font(.title3)
                Text(shown?.album ?? " ")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
        .opacity(play == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.8), value: play == nil)
        .onChange(of: play?.track, initial: true) { _, track in
            // Keep the old Track drawn while fading out; swap in a new one at once.
            if let track { shown = track }
        }
        .accessibilityElement(children: .combine)
    }
}
