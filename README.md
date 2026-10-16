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

Audio capture needs a real iPhone with the deck plugged in. Choose the deck's input in Settings.

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

History shows each Play's status: waiting for Last.fm (pending), scrobbled, rejected by Last.fm, too short to scrobble, or not scrobbled. Plays made while Last.fm isn't connected are never sent later, and nor are those still waiting when you disconnect. If Last.fm stops accepting the session (revoked from your Last.fm settings), Settings says so; connect again and the Plays still waiting are sent.

## Rooms and the stream

Pressing finds Sonos players with Bonjour (`_sonos._tcp`) and lists their Rooms from ZoneGroupTopology. Allow local network access when asked; the shortcut is in Settings. Switch on the Rooms that should play and set each one's volume. When a Record starts a Session, each switched-on Room is pointed at the phone's stream, `x-rincon-mp3radio://<phone-ip>:8020/pressing/turntable.mp3`, at its volume. When the Session ends, they are stopped.

The phone and the speakers must be on the same network, and the phone's IP address must stay the same during a Session.

## Identification

Pressing searches for the Track when a Record starts, after each Gap, and every 30 s otherwise, each time on 8 s of the deck's audio. The current Track shows in the lower third (artist, title and cover) and in the Sonos app as "Artist – Title" under the station name "Pressing". It stays through quiet passages: it is cleared at a Flip, when a different Track matches, or when the search after a Gap and the following recheck both find nothing. Keep the deck's pitch at zero, or Tracks won't match.

## Calibrate detection

Pressing starts a Record when the level stays above the start threshold for the start delay, and ends it with a Flip once the level stays below it for the Flip threshold. The level is the median of 100 ms frames over the last second, so the run-out groove's clicks don't count. Calibrate once per deck and gain setting:

1. Set the deck's USB gain once, so loud passages peak well below clipping. On the Numark TT USB the gain and phono/line switches are on the underside.
2. Keep pitch at zero.
3. Play a Record through to the run-out groove and leave the stylus there with the platter turning.
4. Read the noise floor (the white tick) from the level display on the main screen, and in Settings set the threshold (the orange tick) clearly above it but below the quietest music.

Changing the deck's gain means calibrating again. If the noise floor is high because of hum, try a different charger or socket first: the deck and the phone's charger may form a ground loop.

The start delay (default 1.5 s), Flip threshold (default 12 s) and stop delay (default 45 s of silence, counted from when it began) are in Settings too. The stop delay must be longer than the Flip threshold.
