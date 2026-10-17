import SwiftUI
import FirstPressCore

/// Shown while a Session runs: the current Track, large enough to read from
/// across the room, with History below it.
///
/// At rest the current Track fills the screen but for exactly two rows of
/// History at the bottom: the Track's area is the visible height less two
/// row heights, and every row has that one fixed height. Scrolling down
/// reveals more Plays; the gear and speaker icons stay in the toolbar.
struct NowPlayingView: View {
    let firstPress: FirstPress
    /// Passed in rather than read here, so this view doesn't follow every
    /// change to `state` (the level meter's included).
    let play: Play?

    /// One row of History. Scales with Dynamic Type, and the Track's area
    /// shrinks to match, so two rows still show at rest.
    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = 76

    /// Scrolled into History. Until then its rows are slightly faded, so the
    /// current Track stands out at rest.
    @State private var isScrolled = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    CurrentTrackView(track: play?.track)
                        .padding()
                        .frame(height: max(geometry.size.height - 2 * rowHeight, 0))
                        .background {
                            // Where the top of the content is, to tell rest from scrolled.
                            GeometryReader { top in
                                Color.clear.preference(
                                    key: ScrolledKey.self,
                                    value: top.frame(in: .named(Self.scrollSpace)).minY < -1
                                )
                            }
                        }
                    RecentPlaysList(firstPress: firstPress, current: play?.id, rowHeight: rowHeight)
                        .opacity(isScrolled ? 1 : 0.55)
                        .animation(.easeInOut(duration: 0.3), value: isScrolled)
                }
            }
            .coordinateSpace(.named(Self.scrollSpace))
            .onPreferenceChange(ScrolledKey.self) { isScrolled = $0 }
            .scrollIndicators(.hidden)
            // Keep the third row out of the home indicator's area at rest.
            .clipShape(Rectangle())
        }
    }
}

private extension NowPlayingView {
    static let scrollSpace = "nowPlaying"
}

/// Whether Now Playing is scrolled away from rest.
private struct ScrolledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The current Track, or the app's artwork in grey while there is none. Both
/// take the same space, so nothing moves when a Track appears or goes.
private struct CurrentTrackView: View {
    let track: Track?

    var body: some View {
        VStack(spacing: 24) {
            cover
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 6) {
                // Blank lines hold the space while no Track is identified.
                Text(track?.title ?? " ")
                    .font(.largeTitle.bold())
                Text(track?.artist ?? " ")
                    .font(.title2)
                Text(track?.album ?? " ")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.6), value: track)
        .accessibilityElement(children: .combine)
    }

    /// The Track's artwork, or the app icon's artwork in grey
    /// (Design/NoTrackCover.svg) while there's none.
    private var cover: some View {
        ZStack {
            if let artwork = track?.artworkURL {
                AsyncImage(url: artwork) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    noTrack
                }
            } else {
                noTrack
            }
        }
    }

    private var noTrack: some View {
        Image("NoTrackCover")
            .resizable()
            .scaledToFill()
            .accessibilityLabel("No Track identified")
    }
}

/// History under the current Track: the most recent Plays, newest first,
/// without the current one. Tapping a Play searches Spotify for its Track.
///
/// Reads `history` but not `state`, so the level meter doesn't redraw it.
private struct RecentPlaysList: View {
    let firstPress: FirstPress
    let current: Play.ID?
    let rowHeight: CGFloat
    @Environment(\.openURL) private var openURL

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(FirstPress.recentPlays(in: firstPress.history, excluding: current)) { play in
                Button {
                    openURL(play.track.spotifySearchURL)
                } label: {
                    PlayRow(play: play, cover: firstPress.cover(for: play.track))
                        .padding(.horizontal)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Divider().padding(.leading) }
                .accessibilityHint("Searches Spotify for this Track")
            }
        }
    }
}
