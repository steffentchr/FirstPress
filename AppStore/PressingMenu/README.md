# App Store: Pressing Menu

Everything for Pressing Menu's Mac App Store listing: screenshots, the store text, the listing to paste and the review notes. The privacy policy is shared with the iPhone app and sits one level up, in [`../privacy-policy.md`](../privacy-policy.md). The iPhone app's material is in [`../Pressing/`](../Pressing).

| Path | What it is |
|---|---|
| `demo.json` | Each screenshot's scene and caption, and what the iPhone set's Mac pane shows. The sample world itself (Tracks, sleeves, Rooms) is the iPhone set's, in `../Pressing/demo.json`. |
| `Hook/` | The screenshot hook: `ScreenshotDemo.swift` links the app to a phone that only sends the sample world and renders the panel and Settings to PNGs; `hook.patch` holds the few one-line edits to the app that let it. |
| `screenshots.sh` | Applies the hook, builds the Mac app, runs it once to render, reverts the hook, frames the Mac set, draws the iPhone set's Mac pane and re-frames the iPhone set. |
| `frame.py` | The framing: the desktop, the menu bar, the frosted panel, the notification cards and the captions around the renders. |
| `Screenshots/raw/` | The app's renders at 3 pixels per point: `panel-history.png`, `panel-rooms.png`, `settings.png`. |
| `Screenshots/Mac/` | The framed shots to upload, 2880 × 1800, no alpha. |
| `Metadata/en-US/` | The store text, one field per file, in fastlane `deliver`'s layout. |
| `listing.md` | Promotional Text, Description and Keywords from `Metadata/en-US/`, ready to paste into App Store Connect. |
| `review-notes.md` | The notes for App Review. |

## Regenerate the screenshots

```sh
AppStore/PressingMenu/screenshots.sh               # render, then frame both sets
AppStore/PressingMenu/screenshots.sh --frame-only  # re-frame only, after editing captions
```

A full run takes about a minute. Run it again whenever the panel or Settings changes; it also redraws the iPhone set's last screenshot. It refuses to start if the files the patch edits have uncommitted changes, and reverts them on exit, even after an error. If `hook.patch` no longer applies, redo the edits by hand and save the diff over it with `git diff -- Menu/Sources/PressingMenuApp.swift Menu/Sources/PanelView.swift > AppStore/PressingMenu/Hook/hook.patch`.

Scenes, by the `scene` name in `demo.json`:

| Scene | Shows |
|---|---|
| `panel` | The panel open under its menu-bar icon: the current Track with its sleeve, and History. |
| `rooms` | The panel's Rooms view: This iPhone, two Rooms on at their volumes, one off. |
| `notification` | A new-Track notification, with the app's icon and the sleeve. |
| `settings` | The Settings window. |

App Store Connect takes one Mac size for every Mac, 16:10; 2880 × 1800 is the largest.

### How the shots are made

**The panel and Settings are the real SwiftUI views**, rendered by the app itself through `NSHostingView` in off-screen windows. The hook replaces only the link to the phone, with one that sends a snapshot of the sample world, so the header, History, the Rooms summary and Settings are the app's own. It tells AppKit the app is active, since a menu-bar app started from a script isn't brought to the front and would draw its switches grey, and pins the accent colour to macOS's default blue, whatever the Mac running it uses. Launch at login shows whatever this Mac's login items say for the app.

**Everything around them is drawn by `frame.py`**: an invented wallpaper, a menu bar with Pressing Menu's icon (from `Design/MenuBarIconPlaying.svg`, so it follows the artwork), the frosted backing behind the panel, which the render leaves transparent, and the notification cards. macOS draws the real panel's glass and the real notifications itself, outside the app, so these are drawn to look like them.

**A notification card is data.** `{ "newTrack": "nowPlaying" }` draws a Track as the app posts it: the title, then the artist and the album, with the sleeve. Any other card, such as "Flip the record", is `{ "title": …, "body": …, "image": null }`, with no new code.

**The iPhone set's last screenshot** comes from here: `frame.py` draws a crop of the Mac's screen with a new-Track notification, and the panel's Rooms view below it, as a transparent layer at `../Pressing/Screenshots/raw/06-mac.png`. The iPhone frame step adds the background and its caption from `../Pressing/demo.json`.

## Choices, and why

**The text describes only what Pressing Menu does**, in the root README's and spec #14's words: the panel, notifications (a new Track, and Flip the record), the Rooms view, finding a song, Settings. Anything Pressing itself does (detection, identification, Last.fm) is left to the iPhone app's listing, so a reader isn't promised a Mac app that plays records.

**It says up front that Pressing Menu needs Pressing on an iPhone.** On its own it does nothing, and a buyer who missed that would rightly feel misled. "What you need" repeats it, with macOS 26.

**Privacy wording comes from the approved privacy policy and nowhere else.** The description's one line on it, that Pressing Menu talks only to Pressing on your home network and has no account or server of its own, restates the policy. Any further privacy or security claim goes to the owner first.

**Sonos, Spotify and Apple Music are named in the description, not in the keywords.** They say what Pressing Menu works with, but guideline 2.3.7 rejects other companies' trademarks in keywords. "Remote" is left out of the keywords as well, because the subtitle already carries it.

## Store fields not in files

| Field | Draft |
|---|---|
| Primary category | Music (matches `LSApplicationCategoryType` in `project.yml`) |
| Secondary category | Utilities |
| Age rating | 4+ (every questionnaire answer "None"/"No". Pressing Menu has no web view; clicking a Track opens Spotify or Apple Music in its own app or the browser.) |
| Price | Your call. Pressing Menu is useless without Pressing, so it may be free even if the iPhone app isn't. |
| Availability | Your call. Keep it to the iPhone app's countries. |
| Copyright | `2026 Steffen Fagerström Christensen` |
| App Privacy | See "Open decisions" below. |
| Sign-in required for review | No |
| Minimum macOS | 26, from `project.yml`. |

## Open decisions before submitting

1. **App Privacy label.** Pressing Menu's developer collects nothing: it talks to Pressing on the local network, and downloads a notification's cover from the address Shazam provides. "Data Not Collected" is the likely answer. That's a judgement under Apple's definitions for you to make; this is a recommendation, not a determination.
2. **The name.** "Pressing Menu" must be free on the Mac App Store. If it's taken, "Pressing Menu for Mac" or "Pressing: Menu Bar Remote" fit in 30 characters; the glossary and `project.yml` would follow.
3. **The review video.** `review-notes.md` asks for a link to a short video of Pressing Menu controlling Pressing with a deck and Sonos, like the iPhone app's.
4. **Pressing has to be reachable by App Review.** The review notes need a link to Pressing on the App Store or a TestFlight invitation. If the iPhone app isn't live yet, submit it first, or expect a rejection under guideline 2.1 for an app that can't be tried.
5. **Separate record or a macOS platform on the iPhone app's.** The root README › Releasing Pressing Menu leaves this open. A separate record matches the separate name, bundle ID and price.
6. **Export compliance.** Pressing Menu uses no encryption of its own: its link to the phone is a plain WebSocket on the local network, and the only HTTPS is the system's, for a notification's cover. That is exempt. Setting `ITSAppUsesNonExemptEncryption` to `NO` on the `PressingMenu` target in `project.yml` saves answering the question on every build.
7. **Privacy policy URL.** `Metadata/en-US/privacy_url.txt` and Settings' About footer (`SettingsView.privacyURL`) both point at `AppStore/privacy-policy.md` on GitHub, as the iPhone app's listing does. If the policy moves, change all three.
8. **The privacy policy says "Right-clicking a Track"** opens the search, but the panel now finds a Track on a click. The policy is approved text, so changing it is left to you.
