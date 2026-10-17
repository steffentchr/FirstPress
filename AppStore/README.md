# App Store

Everything for Pressing's App Store listing: screenshots, the sample music in them, the store text, the review notes and the privacy policy. Edit the sources here and regenerate; nothing is made by hand.

| Path | What it is |
|---|---|
| `demo.json` | The sample world the screenshots show: the input's name, the Rooms, the Last.fm user, the current Track, History, and each screenshot's scene and caption. |
| `Covers/*.svg` | The sample sleeves, one per album. A Track names its sleeve by file name in `demo.json`. |
| `Hook/` | The screenshot hook: `ScreenshotDemo.swift` wires the core to the test fakes and plays `demo.json`; `hook.patch` holds the few one-line edits to the app that open a scene. |
| `screenshots.sh` | Applies the hook, builds, shoots each scene in the simulator, frames the shots, and reverts the hook. |
| `Screenshots/raw/` | The simulator's shots, 1320 × 2868. |
| `Screenshots/6.9-inch/` | The framed shots to upload, 1320 × 2868, no alpha. |
| `Metadata/en-US/` | The store text, one field per file, in fastlane `deliver`'s layout. |
| `review-notes.md` | The notes for App Review. |
| `privacy-policy.md` | The privacy policy the store listing links to. |

## Regenerate the screenshots

```sh
AppStore/screenshots.sh               # shoot every scene, then frame
AppStore/screenshots.sh --frame-only  # re-frame only, after editing captions
SIM="iPhone 18 Pro Max" AppStore/screenshots.sh   # another 6.9" simulator
```

A full run takes about three minutes. It refuses to start if the files the patch edits have uncommitted changes, and it reverts them on exit, even after an error. If the app's code moves and `hook.patch` no longer applies, redo the edits by hand (they're short; see the patch) and save the new diff over it with `git diff -- <files> > AppStore/Hook/hook.patch`.

Scenes, by the `scene` name in `demo.json`:

| Scene | Shows |
|---|---|
| `nowPlaying` | A Record playing, its Track identified, two rows of History. |
| `rooms` | The Rooms sheet over Now Playing. |
| `history` | Now Playing scrolled to the bottom of History. |
| `settings` | Settings at full height, with Last.fm connected. |
| `waiting` | The start screen, input ready. |

App Store Connect needs only the 6.9" set for an iPhone-only app; it scales it down for smaller iPhones.

## Choices, and why

**The sample music is invented, and nods to The Smiths.** Real artists and real sleeves in store screenshots invite a rejection under guideline 5.2 (intellectual property), so every artist, album, Track and sleeve here is made up. They wink at The Smiths without copying anything:

- The band is **The Joneses**: the other everyman surname.
- The hero album, **The King Is Asleep**, answers *The Queen Is Dead*. Its sleeve follows that one's formula: a single-colour green still of a man lying on his back, the band name in white and the title in pale pink above. It's drawn from scratch; no part of the original sleeve or its photograph is used.
- The other sleeves follow the Smiths singles' formula, a tinted "cover star" still in one colour with the name in plain white capitals: *Sideways, Here We Go* (blue; *Strangeways, Here We Come*), *Quieter Than Moths* (rose; *Louder Than Bombs*), *Hatful of Borrow* (ochre; *Hatful of Hollow*).
- The Track titles bend Smiths titles: *Heaven Knows I'm Fine Now*, *How Soon Is Later*, *This Charming Van*, *Ask Me Twice*, *Still Fine*, *Garden Gates*, *Panic on the Escalator*, *Bigmouth Strikes Twice*, *Hat in Hand*.

Keep it to nods. A real band name, a real title or anything traced from a real sleeve would undo the point of inventing them.

**The input is "USB Audio".** A generic name fits any deck or interface, where a brand name like "Numark TT USB" would suggest one model is required. Settings shows it as "USB Audio (USB)".

**The Rooms are Living Room, Kitchen and Study**, two on at different volumes and one off, so a single shot shows both multiroom and per-Room volume.

**Screenshots run in the simulator on the real core.** The hook replaces only the ports (input, Sonos, Shazam, Last.fm, storage) with the test fakes, so detection, identification, History and the screens are the app's own. The status bar is set to 9:41, full signal and charged, with the simulator in US English and dark mode.

**Captions say what Pressing does, in the README's words**, at most two short lines each, in Helvetica Neue Bold on the icon's orange gradient. Sonos and Last.fm are named in captions and the description, because they say what Pressing works with, but they're kept out of the keywords: guideline 2.3.7 rejects other companies' trademarks there.

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

1. **App Privacy label.** Pressing's developer collects nothing, but Last.fm receives what you play under your account once you connect it, and ShazamKit sends audio signatures to Apple. "Data Not Collected" is the likely answer, since both go to services you use directly. That's a judgement under Apple's definitions for you to make; this is a recommendation, not a determination.
2. **Export compliance.** Pressing uses only HTTPS and an MD5 signature for Last.fm, which is exempt. Setting `ITSAppUsesNonExemptEncryption` to `NO` (in `project.yml`, as `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`) saves answering the question on every build.
3. **LAME is LGPL.** Pressing links LAME statically. The LGPL requires that users can relink the app against a modified LAME, which App Store distribution makes hard. Get this settled before release, for example by publishing the object files or shipping LAME as a dynamic framework.
4. **Licence for Pressing's own code.** The root README says none is chosen yet.
5. **Last.fm API terms.** Read them for an app sold or distributed publicly, and check that the bundled API key is one you're allowed to ship.
6. **The name.** "Pressing" must be free on the App Store. If it's taken, "Pressing: Vinyl to Sonos" fits in 30 characters.
7. **Privacy policy URL.** `Metadata/en-US/privacy_url.txt` points at `privacy-policy.md` on GitHub, which works because the repo is public. A GitHub Pages URL would look tidier.
8. **The review video.** `review-notes.md` asks for a link to a short video of Pressing with a deck and Sonos.
9. **The root README** still says Pressing isn't on the App Store.
