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

## Rooms and the stream

Pressing finds Sonos players with Bonjour (`_sonos._tcp`) and lists their Rooms from ZoneGroupTopology. Allow local network access when asked; the shortcut is in Settings. Switch on the Rooms that should play and set each one's volume. When a Record starts a Session, each switched-on Room is pointed at the phone's stream, `x-rincon-mp3radio://<phone-ip>:8020/pressing/turntable.mp3`, at its volume. When the Session ends, they are stopped.

The phone and the speakers must be on the same network, and the phone's IP address must stay the same during a Session.

## Identification

Pressing searches for the Track when a Record starts, after each Gap, and every 30 s otherwise, each time on 8 s of the deck's audio. The current Track shows in the lower third (artist, title and cover) and in the Sonos app as "Artist – Title" under the station name "Pressing". It stays through quiet passages: it is cleared at a Flip, when a different Track matches, or when the search after a Gap and the following recheck both find nothing. Keep the deck's pitch at zero, or Tracks won't match.

## Calibrate detection

Pressing starts a Record when the level stays above the start threshold for the start delay, and ends it with a Flip once the level stays below it for the Flip threshold. The level is the median of 100 ms frames over the last second, so the run-out groove's clicks don't count. Calibrate once per deck and gain setting:

1. Set the deck's USB gain once, so loud passages peak well below clipping. On the Numark TT USB the gain and phono/line switches are on the underside.
2. Keep pitch at zero.
3. Play a side through to the run-out and leave the stylus there with the platter turning.
4. Read the noise floor (the white tick) from the level display on the main screen, and in Settings set the threshold (the orange tick) clearly above it but below the quietest music.

Changing the deck's gain means calibrating again. If the noise floor is high because of hum, try a different charger or socket first: the deck and the phone's charger may form a ground loop.

The start delay (default 1.5 s), Flip threshold (default 12 s) and stop delay (default 45 s of silence, counted from when it began) are in Settings too. The stop delay must be longer than the Flip threshold.
