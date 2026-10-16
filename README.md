# Pressing

Pressing is an iPhone bridge from your record deck to Sonos speakers.

All behaviour lives in `PressingCore`, a Swift package with no UIKit or SwiftUI. The app in `App/` is a thin SwiftUI shell plus the production adapters for the core's ports.

## Run the tests

```sh
swift test --package-path PressingCore
```

Runs on macOS; no simulator needed.

## Build the app

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig` and fill in your bundle ID and team ID. The copy is git-ignored. Without it, the app still builds for the simulator with a placeholder bundle ID.
3. Generate the project with `xcodegen generate`, then open `Pressing.xcodeproj`. The project is generated from `project.yml` and not checked in. Run `xcodegen generate` again after pulling changes to it.

   The first `xcodegen generate` also builds the MP3 encoder: `scripts/build-lame.sh` downloads LAME 3.100, checks its SHA-256, and cross-compiles it into `Vendor/LAME.xcframework` (iOS device, simulator and macOS). This takes about a minute and needs the network once. The framework is git-ignored. To rebuild it, run `scripts/build-lame.sh` yourself.

To build for the simulator from the command line:

```sh
xcodebuild -project Pressing.xcodeproj -scheme Pressing \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Audio capture needs a real iPhone with the deck plugged in.

## The screens

Pressing is an appliance with one screen at a time.

- **Choose input.** On first launch Pressing asks for the input before it starts anything else: it asks for the microphone, which listing the inputs needs, and only looks for Sonos Rooms once an input is chosen. Tap "Choose the input" and pick the deck's input from the menu. The same screen comes back, saying the input isn't connected, whenever the chosen input disappears while no Record is playing, and goes away by itself once it is plugged back in.
- **Waiting.** The input is ready and no Record is playing. The chosen input's name shows under "Drop the needle to start"; tap it to switch to another input at once, with the same choices as Settings. While the chosen input isn't connected, its name is marked "Not connected".
- **Now Playing.** Shown by itself while a Session runs: the current Track, large. While no Track is identified (before the first match, between Tracks, after a Flip, or for a Record Shazam doesn't know) a generic record and "Listening…" take its place, so nothing moves when a Track appears. Below it is History: at rest the two most recent Plays sit at the bottom of the screen, and scrolling down reveals more, up to the 50 most recent. The current Play isn't repeated there. Tap a Play to search Spotify for its Track; it opens the Spotify app when it's installed. The screen stays through Gaps and Flips and gives way to the waiting screen when the Session ends. If the input disappears mid-Session, Now Playing stays until the Session ends.

The waiting and Now Playing screens have two icons in the top right. The speaker opens the Rooms: switch each on or off and set its volume, mid-Session too. It also shows which Rooms Pressing stepped back from and which can't be reached. The gear opens Settings: the input, screen blanking and Last.fm, with Detection and Permissions in submenus. An open sheet stays open when the screen changes underneath it.

The screen blanks after the time set in Settings once no Record is playing, never while one plays. A touch wakes it without pressing anything; so does a Record starting, or coming back to Pressing from another app.

### Enable ShazamKit for your App ID

Pressing identifies Tracks against the Shazam catalog, which only answers apps whose App ID has the ShazamKit App Service. Without it, nothing is identified. Do this once for the bundle ID you put in `Config/Signing.xcconfig`:

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account) and open **Certificates, IDs & Profiles → Identifiers**.
2. Select the App ID for your bundle ID (create it if Xcode hasn't yet).
3. Open the **App Services** tab, tick **ShazamKit**, and save.

No entitlement or Info.plist key is needed for the Shazam catalog. Apple's guide is [Enable ShazamKit for an App ID](https://developer.apple.com/help/account/configure-app-services/shazamkit). Identification also needs the phone online, since Shazam matches on Apple's servers.

### Set up the Last.fm API account

Pressing scrobbles to Last.fm with its own API account. The key and secret are build configuration and are never committed:

1. Sign in at Last.fm and create an API account at [last.fm/api/account/create](https://www.last.fm/api/account/create). Name the application "Pressing". The callback URL can stay empty: Pressing passes its own callback, `pressing://lastfm-auth`, when it opens the sign-in page.
2. Copy `Config/LastFm.xcconfig.example` to `Config/LastFm.xcconfig` and fill in the API key and shared secret from [last.fm/api/accounts](https://www.last.fm/api/accounts). The copy is git-ignored.
3. Build again. The values reach the app through `App/Info.plist` (`LastFmAPIKey`, `LastFmAPISecret`).

Without `Config/LastFm.xcconfig` the app still builds, and Settings says Last.fm isn't available in this build. The secret ends up inside the built app, as it does for any app that signs Last.fm calls on the phone; keep builds to your own devices.

## Last.fm

Connect Last.fm in Settings. Pressing opens Last.fm's own sign-in page, so it never sees your password, and keeps the session key in the Keychain. If the page doesn't close by itself after you approve Pressing, close it: Pressing then finishes connecting. Disconnect in Settings to stop scrobbling.

When a Play starts while Last.fm is connected, Pressing sends "now playing" and asks Last.fm for the Track's length and album; the album fills in the Play, since Shazam gives none. The Play is scrobbled once it qualifies: the Track is longer than 30 s and has played for half its length or 4 minutes, whichever comes first. If Last.fm doesn't know the length, it qualifies at 4 minutes, or at its end if it ran at least 30 s. Plays waiting for Last.fm are queued across a restart, go in batches of up to 50, and are retried with backoff and as soon as the network returns.

History, on Now Playing, shows each Play's start (with its day, for Plays before today) and its status: waiting for Last.fm (pending), scrobbled, rejected by Last.fm, too short to scrobble, or not scrobbled. Plays made while Last.fm isn't connected are never sent later, and nor are those still waiting when you disconnect. If Last.fm stops accepting the session (revoked from your Last.fm settings), Settings says so; connect again and the Plays still waiting are sent.

## Rooms and the stream

Pressing finds Sonos players with Bonjour (`_sonos._tcp`) and lists their Rooms from ZoneGroupTopology. It starts looking once an input is chosen. Allow local network access when asked; the shortcut is in Settings › Permissions. Tap the speaker icon to switch on the Rooms that should play and set each one's volume. When a Record starts a Session, each switched-on Room is pointed at the phone's stream, `x-rincon-mp3radio://<phone-ip>:8020/pressing/turntable.mp3`, at its volume. When the Session ends, they are stopped.

The phone and the speakers must be on the same network, and the phone's IP address must stay the same during a Session.

## Identification

Pressing searches for the Track when a Record starts, after each Gap, and every 30 s otherwise, each time on 8 s of the deck's audio. The current Track shows on the Now Playing screen (cover, title, artist and album) and in the Sonos app as "Artist – Title" under the station name "Pressing". It stays through quiet passages: it is cleared at a Flip, when a different Track matches, or when the search after a Gap and the following recheck both find nothing. Keep the deck's pitch at zero, or Tracks won't match.

## Calibrate detection

Pressing starts a Record when the level stays above the start threshold for the start delay, and ends it with a Flip once the level stays below it for the Flip threshold. The level is the median of 100 ms frames over the last second, so the run-out groove's clicks don't count. Calibrate once per deck and gain setting:

1. Set the deck's USB gain once, so loud passages peak well below clipping. On the Numark TT USB the gain and phono/line switches are on the underside.
2. Keep pitch at zero.
3. Play a Record through to the run-out groove and leave the stylus there with the platter turning.
4. Read the noise floor (the white tick) from the level display in Settings › Detection, and there set the threshold (the orange tick) clearly above it but below the quietest music.

Changing the deck's gain means calibrating again. If the noise floor is high because of hum, try a different charger or socket first: the deck and the phone's charger may form a ground loop.

The start delay (default 1.5 s), Flip threshold (default 12 s) and stop delay (default 45 s of silence, counted from when it began) are in Settings › Detection too. The stop delay must be longer than the Flip threshold.
