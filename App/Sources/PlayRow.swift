import SwiftUI
import UIKit
import PressingCore

/// One Play: cover, artist, title, album when known, when it started and
/// scrobble status. The list has no day headers, so a Play from before
/// today shows its day too.
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

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Self.started(play.startedAt))
                    .font(.subheadline.monospacedDigit())
                ScrobbleStatusLabel(status: play.scrobble)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "21:03" today, "Mon 21:03" this past week, "12 Oct" before that.
    static func started(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return date.formatted(sameYear ? style : style.year())
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

/// Whether the Play reached Last.fm.
struct ScrobbleStatusLabel: View {
    let status: ScrobbleStatus

    var body: some View {
        let look = look
        Label(look.text, systemImage: look.symbol)
            .labelStyle(.iconOnly)
            .font(.footnote)
            .foregroundStyle(look.color)
            .accessibilityLabel(look.text)
    }

    /// How each status shows: what it says, its symbol and its colour.
    private var look: (text: String, symbol: String, color: Color) {
        switch status {
        case .pending: ("Waiting for Last.fm", "clock", .secondary)
        case .scrobbled: ("Scrobbled", "checkmark.circle.fill", .green)
        case .rejected: ("Rejected by Last.fm", "xmark.circle", .orange)
        case .notEligible: ("Too short to scrobble", "minus.circle", .secondary)
        case .notScrobbled: ("Not scrobbled", "circle.dashed", .secondary)
        }
    }
}
