import SwiftUI
import UIKit
import PressingCore

/// Every Play kept on the phone, newest first, under a header per day.
/// Reached by swiping left from the main screen.
struct HistoryView: View {
    let pressing: Pressing

    var body: some View {
        NavigationStack {
            Group {
                if pressing.history.isEmpty {
                    ContentUnavailableView(
                        "No Plays yet",
                        systemImage: "opticaldisc",
                        description: Text("Every Track Pressing identifies is kept here.")
                    )
                } else {
                    List {
                        ForEach(HistoryDay.days(of: pressing.history)) { day in
                            Section(Self.header(for: day.day)) {
                                ForEach(day.plays) { play in
                                    PlayRow(play: play, cover: pressing.cover(for: play.track))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
        }
    }

    private static func header(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return day.formatted(sameYear ? style : style.year())
    }
}

/// One Play: cover, artist, title, album when known, time and scrobble status.
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
                Text(play.startedAt, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                ScrobbleStatusLabel(status: play.scrobble)
            }
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

/// Whether the Play reached Last.fm.
struct ScrobbleStatusLabel: View {
    let status: ScrobbleStatus

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.footnote)
            .foregroundStyle(color)
            .accessibilityLabel(text)
    }

    private var text: String {
        switch status {
        case .pending: "Waiting for Last.fm"
        case .scrobbled: "Scrobbled"
        case .rejected: "Rejected by Last.fm"
        case .notEligible: "Too short to scrobble"
        case .notScrobbled: "Not scrobbled"
        }
    }

    private var symbol: String {
        switch status {
        case .pending: "clock"
        case .scrobbled: "checkmark.circle.fill"
        case .rejected: "xmark.circle"
        case .notEligible: "minus.circle"
        case .notScrobbled: "circle.dashed"
        }
    }

    private var color: Color {
        switch status {
        case .scrobbled: .green
        case .rejected: .orange
        default: .secondary
        }
    }
}
