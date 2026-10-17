# Notes for App Review

Paste into App Store Connect › App Review Information › Notes. No sign-in is needed.

---

First Press streams a record playing on a USB turntable to Sonos speakers on the same Wi-Fi network. The full setup needs a turntable with USB audio and Sonos speakers, but you can see First Press work without them:

1. On the start screen, choose "iPhone Microphone (picks up the room)" as the input and allow microphone access.
2. Allow local network access when asked. (With no Sonos speakers, the Rooms list stays empty; that is expected.)
3. Play music aloud near the phone, from another device. After about 2 seconds First Press shows Now Playing; within about 30 seconds Shazam identifies the Track and its cover, title and artist appear.
4. Tap the speaker icon and tick "This iPhone" to hear the input played back through the phone's speaker or AirPlay.
5. Stop the music: after 12 seconds of silence First Press waits for a flip, and after 45 seconds it returns to the start screen. The Track is now in History under Now Playing.

Last.fm is optional and uses the reviewer's own Last.fm account, signing in on Last.fm's own web page.

The microphone is used only for the input the user picks, and only to detect and stream the record. Audio is never stored. Local network access is used to find Sonos speakers (Bonjour, _sonos._tcp) and control them over their local UPnP interface.

A video of First Press with a turntable and Sonos speakers: <ADD LINK BEFORE SUBMITTING>
