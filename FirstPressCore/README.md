# FirstPressCore

All of First Press's behaviour, as a Swift package that imports only Foundation, Observation and CryptoKit. It has no UIKit or SwiftUI, so it builds and tests on macOS without a simulator. The iPhone app in [`../App`](../App) is a thin SwiftUI shell around it.

```sh
swift test --package-path FirstPressCore
```

## Shape

- **`FirstPress`** is the one public entry point, and an `@Observable` class.
  - The app creates it with the ports, calls `start()` once, and forwards what the listener does as intents: `chooseInput`, `switchRoom`, `setVolume`, `setKiosk`, `screenTouched`, `cameToForeground`, and so on.
  - It publishes one `state` snapshot (`FirstPressState`), which includes `page`, the screen the app should show.
  - History is published separately (`history`, `recentPlays`), so the level meter's updates don't redraw it.
- **Ports** (in `Sources/FirstPressCore/Ports`) are the only way the core reaches the outside world. The app supplies the real adapters, and the tests supply fakes.

  | Port | Covers |
  |---|---|
  | `AudioInput` | The deck's input: buffers, available inputs, route changes |
  | `SonosNetwork` | Discovery events, and SOAP requests to the speakers |
  | `StreamSink` | The live MP3 stream served to the Rooms |
  | `PhoneOutput` | Playing the Record on the phone itself, and where it plays (the route) |
  | `Recognizer` | ShazamKit matching |
  | `ArtworkDownloader` | Covers |
  | `LastFmHTTP`, `WebAuth`, `Keychain` | Last.fm calls, sign-in and the stored session |
  | `Store` | Settings, History and the scrobble queue |
  | `Scheduler` | Time and timers |
  | `MenuServer` | First Press Menus connected over the network: snapshots out, commands (Rooms, volumes, This iPhone) in |

- **`FirstPressMenuCore`** is a second library product: First Press Menu's model (`FirstPressMenu`), which its views render. It reaches the phone only through its `MenuLink` port, posts notifications through its `MenuNotifier` port, and shares the wire types (`MenuSnapshot`, `MenuWire`) with the core. Like the core, it imports only Foundation and Observation. See ADR-0004.
- **Protocol logic lives here, not in the adapters.** That covers the SOAP envelopes, ICY stream framing, Last.fm request signing, detection, resampling and First Press Menu's wire contract. The adapters only move bytes and call system APIs, so the logic is tested.

## Tests

Tests use Swift Testing and drive `FirstPress` through its public interface only. There's no `@testable import`. A good test plays a listening scenario through the fakes and checks what the outside world sees, for example:
- seconds of signal fed through `FakeAudioInput`, with time moved by `FakeScheduler`;
- the requests a fake Sonos household receives;
- the bytes a stream client reads;
- the published state and stored Plays;
- what a First Press Menu shows, joined to a real `FirstPress` by an in-memory link (`FakeMenuLink`, `World.firstPressMenu()`).

The fakes live in `Tests/FirstPressCoreTests/Fakes`. `FakeSonos` models the parts of real Sonos behaviour that matter to First Press: groups, members refusing playback commands with error 800, and members always reporting PLAYING.

New behaviour is built test-first at this seam. Domain words in names and test titles follow [`../GLOSSARY.md`](../GLOSSARY.md).
