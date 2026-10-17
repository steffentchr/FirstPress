# App Store: Pressing Menu

Everything for Pressing Menu's Mac App Store listing: the store text, the listing to paste and the review notes. The privacy policy is shared with the iPhone app and sits one level up, in [`../privacy-policy.md`](../privacy-policy.md). The iPhone app's material is in [`../Pressing/`](../Pressing).

| Path | What it is |
|---|---|
| `Metadata/en-US/` | The store text, one field per file, in fastlane `deliver`'s layout. |
| `listing.md` | Promotional Text, Description and Keywords from `Metadata/en-US/`, ready to paste into App Store Connect. |
| `review-notes.md` | The notes for App Review. |

There are no Mac screenshots yet. They'll be rendered from the real panel, with the same invented sample world as the iPhone set (`../Pressing/demo.json`), and added here.

## Choices, and why

**The text describes only what Pressing Menu does**, in the root README's and spec #14's words: the panel, notifications, the Rooms view, finding a song, Settings. Anything Pressing itself does (detection, identification, Last.fm) is left to the iPhone app's listing, so a reader isn't promised a Mac app that plays records.

**It says up front that Pressing Menu needs Pressing on an iPhone.** On its own it does nothing, and a buyer who missed that would rightly feel misled. "What you need" repeats it, with macOS 26.

**Privacy wording comes from the approved privacy policy and nowhere else.** The description's one line on it, that Pressing Menu talks only to Pressing on your home network and has no account or server of its own, restates the policy. Any further privacy or security claim goes to the owner first.

**Sonos, Spotify and Apple Music are named in the description, not in the keywords.** They say what Pressing Menu works with, but guideline 2.3.7 rejects other companies' trademarks in keywords. "Remote" is left out of the keywords as well, because the subtitle already carries it.

## Store fields not in files

| Field | Draft |
|---|---|
| Primary category | Music (matches `LSApplicationCategoryType` in `project.yml`) |
| Secondary category | Utilities |
| Age rating | 4+ (every questionnaire answer "None"/"No". Pressing Menu has no web view; a right-click opens Spotify or Apple Music in its own app or the browser.) |
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
