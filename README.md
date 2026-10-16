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

To build for the simulator from the command line:

```sh
xcodebuild -project Pressing.xcodeproj -scheme Pressing \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Audio capture needs a real iPhone with the deck plugged in. Choose the deck's input in Settings.

## Calibrate detection

Pressing starts a Record when the level stays above the start threshold for the start delay, and ends it with a Flip once the level stays below it for the Flip threshold. The level is the median of 100 ms frames over the last second, so the run-out groove's clicks don't count. Calibrate once per deck and gain setting:

1. Set the deck's USB gain once, so loud passages peak well below clipping. On the Numark TT USB the gain and phono/line switches are on the underside.
2. Keep pitch at zero.
3. Play a side through to the run-out and leave the stylus there with the platter turning.
4. Read the noise floor (the white tick) from the level display on the main screen, and in Settings set the threshold (the orange tick) clearly above it but below the quietest music.

Changing the deck's gain means calibrating again. If the noise floor is high because of hum, try a different charger or socket first: the deck and the phone's charger may form a ground loop.

The start delay (default 1.5 s), Flip threshold (default 12 s) and stop delay (default 45 s after a Flip) are in Settings too. The stop delay must be longer than the Flip threshold.
