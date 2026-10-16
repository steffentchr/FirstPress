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
