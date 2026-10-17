# App Store: First Press

Everything for the iPhone app's App Store listing: screenshots, the sample music in them, the store text and the review notes. The privacy policy is shared with First Press Menu and sits one level up, in [`../privacy-policy.md`](../privacy-policy.md). Edit the sources here and regenerate; nothing is made by hand.

| Path | What it is |
|---|---|
| `demo.json` | The sample world the screenshots show: the input's name, the Rooms, the Last.fm user, the current Track, History, and each screenshot's scene and caption. First Press Menu's screenshots show the same world. |
| `Covers/*.svg` | The sample sleeves, one per album. A Track names its sleeve by file name in `demo.json`. |
| `Hook/` | The screenshot hook: `ScreenshotDemo.swift` wires the core to the test fakes and plays `demo.json`; `hook.patch` holds the few one-line edits to the app that open a scene. |
| `screenshots.sh` | Applies the hook, builds, shoots each scene in the simulator, frames the shots, and reverts the hook. |
| `Screenshots/raw/` | The simulator's shots, 1320 × 2868, and `06-mac.png`, the Mac layer of the last screenshot, drawn by `../FirstPressMenu/screenshots.sh`. |
| `Screenshots/6.9-inch/` | The framed shots to upload, 1320 × 2868, no alpha. |
| `Metadata/en-US/` | The store text, one field per file, in fastlane `deliver`'s layout. |
| `listing.md` | Promotional Text, Description and Keywords from `Metadata/en-US/`, ready to paste into App Store Connect. |
| `review-notes.md` | The notes for App Review. |

## Regenerate the screenshots

```sh
AppStore/FirstPress/screenshots.sh               # shoot every scene, then frame
AppStore/FirstPress/screenshots.sh --frame-only  # re-frame only, after editing captions
SIM="iPhone 18 Pro Max" AppStore/FirstPress/screenshots.sh   # another 6.9" simulator
```

A full run takes about three minutes. It refuses to start if the files the patch edits have uncommitted changes, and it reverts them on exit, even after an error. If the app's code moves and `hook.patch` no longer applies, redo the edits by hand (they're short; see the patch) and save the new diff over it with `git diff -- <files> > AppStore/FirstPress/Hook/hook.patch`.

Scenes, by the `scene` name in `demo.json`:

| Scene | Shows |
|---|---|
| `nowPlaying` | A Record playing, its Track identified, two rows of History. |
| `rooms` | The Rooms sheet over Now Playing. |
| `history` | Now Playing scrolled to the bottom of History. |
| `settings` | Settings at full height, with Last.fm connected. |
| `waiting` | The start screen, input ready. |
| `mac` | Not shot here: First Press Menu on a Mac, with a new-Track notification and the panel's Rooms view. Its `"from": "FirstPressMenu"` says `../FirstPressMenu/screenshots.sh` draws it into `raw/`; this script only frames it. Regenerate it from there, which re-frames this set too. A scene `from` elsewhere must come after the shot ones. |

App Store Connect needs only the 6.9" set for an iPhone-only app; it scales it down for smaller iPhones.

## Choices, and why

**The sample music is invented, and nods to The Smiths.** Real artists and real sleeves in store screenshots invite a rejection under guideline 5.2 (intellectual property), so every artist, album, Track and sleeve here is made up. They wink at The Smiths without copying anything:

- The band is **The Wrights**. Smith and Wright are both old makers' surnames, so the name sits beside The Smiths without copying it.
- The hero album, **The King Is Dead**, answers *The Queen Is Dead*. Its sleeve follows that one's formula: a single-colour green still of a man lying on his back, the band name in white and the title in pale pink above. It's drawn from scratch; no part of the original sleeve or its photograph is used.
- The other sleeves follow the Smiths singles' formula, a tinted "cover star" still in one colour with the name in plain white capitals: *Sideways, Here We Go* (blue; *Strangeways, Here We Come*), *Quieter Than Moths* (rose; *Louder Than Bombs*), *Hatful of Borrow* (ochre; *Hatful of Hollow*).
- The Track playing is *Bigmouth*, leaning on *Bigmouth Strikes Again*, the single from *The Queen Is Dead*.
- The other Track titles are plain and sincere, not puns: Manchester streets, buses, rain and Sundays, in the band's mood rather than its words. *Under the Iron Bridge*, *Whitworth Street in the Rain*, *A Coat Too Thin for March*, *The Last Bus Out of Salford*, *Nobody Calls on Sundays*, *Bicycles in the Hallway*, *Late Light on the Canal*, *Letters I Never Sent*.
- The record on the start screen and on Now Playing's grey cover (not the app icon) has "ROUGH 96 B-1U-1-1" printed faintly round its label: *The Queen Is Dead*'s Rough Trade catalogue number. It lives in `Design/StartScreen.svg` and `Design/NoTrackCover.svg`.

Keep it to nods. A real band name, a full real title or anything traced from a real sleeve would undo the point of inventing them.

**The input is "USB Audio".** A generic name fits any deck or interface, where a brand name like "Numark TT USB" would suggest one model is required. Settings shows it as "USB Audio (USB)".

**The Rooms are Living Room, Kitchen and Study**, two on at different volumes and one off, so a single shot shows both multiroom and per-Room volume.

**Screenshots run in the simulator on the real core.** The hook replaces only the ports (input, Sonos, Shazam, Last.fm, storage) with the test fakes, so detection, identification, History and the screens are the app's own. The status bar is set to 9:41, full signal and charged, with the simulator in US English and dark mode.

**Captions say what First Press does, in the README's words**, at most two short lines each, in Helvetica Neue Bold on the icon's orange gradient. Sonos and Last.fm are named in captions and the description, because they say what First Press works with, but they're kept out of the keywords: guideline 2.3.7 rejects other companies' trademarks there.

## Store fields not in files

| Field | Draft |
|---|---|
| Primary category | Music |
| Secondary category | Utilities |
| Age rating | 4+ (every questionnaire answer "None"/"No". The Last.fm sign-in is a single authentication page, not unrestricted web access.) |
| Price | Your call. |
| Availability | Your call. |
| Copyright | `2026 Steffen Fagerström Christensen` |
| App Privacy | See "Open decisions" below. |
| Sign-in required for review | No |

## Open decisions before submitting

1. **App Privacy label.** First Press's developer collects nothing, but Last.fm receives what you play under your account once you connect it, and ShazamKit sends audio signatures to Apple. "Data Not Collected" is the likely answer, since both go to services you use directly. That's a judgement under Apple's definitions for you to make; this is a recommendation, not a determination.
2. **Export compliance.** First Press uses only HTTPS and an MD5 signature for Last.fm, which is exempt. Setting `ITSAppUsesNonExemptEncryption` to `NO` (in `project.yml`, as `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`) saves answering the question on every build.
3. **LAME is LGPL.** First Press links LAME statically. The LGPL requires that users can relink the app against a modified LAME, which App Store distribution makes hard. Get this settled before release, for example by publishing the object files or shipping LAME as a dynamic framework.
4. **Licence for First Press's own code.** The root README says none is chosen yet.
5. **Last.fm API terms.** Read them for an app sold or distributed publicly, and check that the bundled API key is one you're allowed to ship.
6. **The name.** "First Press" must be free on the App Store. If it's taken, "First Press: Vinyl to Sonos" fits in 30 characters.
7. **Privacy policy URL.** `Metadata/en-US/privacy_url.txt` points at `AppStore/privacy-policy.md` on GitHub, which works because the repo is public. First Press Menu's listing and its Settings link to the same file, so if it moves, change all three. A GitHub Pages URL would look tidier.
8. **The review video.** `review-notes.md` asks for a link to a short video of First Press with a deck and Sonos.
9. **The root README** still says First Press isn't on the App Store.
