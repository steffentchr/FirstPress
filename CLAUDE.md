# Pressing

Pressing is an iPhone bridge from your record deck to Sonos speakers. `README.md` covers what it does, installing it, the artwork and the development commands. `PressingCore/README.md` covers the core's shape and tests.

## How the code is built

- **One headless core, one test seam.** All behaviour lives in `PressingCore`. It imports only Foundation, Observation and CryptoKit, and reaches the outside world only through the ports in `PressingCore/Sources/PressingCore/Ports`.
  - Build new behaviour test-first (the `tdd` skill) against `Pressing`'s public interface, with the fakes in `Tests/PressingCoreTests/Fakes`. Tests never use `@testable`.
  - Put protocol logic in the core and keep adapters thin. Protocol logic means SOAP, ICY framing, Last.fm signing, detection and the screen rules.
- **The app is a thin shell.** `App/Sources` holds SwiftUI views plus the adapters for the ports. `RootView` shows the page the core names in `state.page`.
- **Domain words come from `GLOSSARY.md`.** Use them in names, test titles, issues and docs: Record (one side of an LP), Gap, Flip, Session, Track, Play, Room, Takeover, Step back, Phone output.

## Working here

- **Commit on `main` and push** after each unit of work. There are no feature branches.
- **The Xcode project is generated.** `project.yml` is the source and the `.xcodeproj` is git-ignored, so after adding, removing or renaming a Swift file, run `xcodegen generate` before building.
- **`Vendor/LAME.xcframework` is git-ignored.** A fresh git worktree lacks it: copy it from the main checkout, or run `scripts/build-lame.sh`.
- **Done means:** `swift test --package-path PressingCore` passes, and the simulator build from `README.md › Development` succeeds.
- **Checking views in the simulator:** you can install the app and take screenshots with `xcrun simctl`, but you can't tap. To reach a sheet or state, add a temporary launch-argument hook, take the screenshot, then remove the hook before committing.
- **Stay off real hardware.** Send nothing to real Sonos speakers or the Last.fm API. Anything that needs the phone, the deck or the speakers becomes a device check for the owner to run: list it under the ticket's acceptance criteria, or in a device-test checklist issue modelled on #10, the first full pass (closed).
- **Editing an issue the owner ticks boxes in:** read its live body first and change only unticked lines. Overwriting the body loses the owner's ticks.
- **Artwork:** SVG sources are in `Design/`, rendered into `App/Resources/Assets.xcassets`. The commands are in `README.md › Artwork`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `steffentchr/Pressing`, operated through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage labels are used as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
