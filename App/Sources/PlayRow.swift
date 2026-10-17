import SwiftUI
import UIKit
import FirstPressCore

/// One Play: cover, title, artist and album when known.
struct PlayRow: View {
    let play: Play
    /// The cover kept on the phone, if it was downloaded.
    let cover: Data?

    var body: some View {
        HStack(spacing: 12) {
            coverImage
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(play.track.title).font(.headline)
                Text(play.track.artist).font(.subheadline)
                if let album = play.track.album, !album.isEmpty {
                    Text(album).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let cover, let image = UIImage(data: cover) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            // Not kept yet (or the download failed): try the artwork URL.
            AsyncImage(url: play.track.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
        }
    }
}
