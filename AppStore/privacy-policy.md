# Pressing privacy policy

_Draft, 17 October 2026. Not yet reviewed._

Pressing has no account, no server and no analytics of its own. Its developer receives no data from it.

## What stays on your iPhone

- **Audio from the input you choose.** Pressing listens to that input only, to detect records and stream them to your speakers. It never records to a file, and the stream goes only to speakers and the phone on your own network.
- **Your History** (the Tracks you've played) and your settings. They're kept on the phone and deleted with the app.
- **Your Last.fm session key**, in the iPhone's Keychain, if you connect Last.fm.

## What goes to other services, and only when you use them

- **Apple (Shazam).** To identify a Track, Pressing sends a short audio signature (not the audio itself) to Apple's ShazamKit service. Apple's privacy policy applies.
- **Last.fm**, if you connect it. Pressing sends the artist, title, album and time of each Track you play, under your Last.fm account. You sign in on Last.fm's own page; Pressing never sees your password. Disconnect at any time in Settings. Last.fm's privacy policy applies.
- **Cover art** is downloaded from the address Shazam provides.
- **Spotify or Apple Music.** Tapping a Track in History opens a Spotify search for it, in Spotify or your browser. Pressing Menu opens a search in Spotify or Apple Music, whichever you choose.

## Your local network

Pressing finds and controls Sonos speakers on your home network. Nothing about them leaves your network.

## Pressing Menu on your Mac

Pressing Menu is a menu-bar app that shows and controls Pressing on your iPhone. Like Pressing, it has no account, no server and no analytics of its own, and its developer receives no data from it.

- **It only talks to Pressing on your home network.** Pressing on your iPhone advertises itself on the local network. Pressing Menu finds it there and connects directly. The phone sends the current Track, your recent Plays and the state of your Rooms. Pressing Menu sends back the changes you make to Rooms, volumes and This iPhone. None of this leaves your network.
- **Anyone on your home network can see and control it.** There's no pairing, so any copy of Pressing Menu on the same network can see what you're playing and switch Rooms and volumes. This is the same trust your home network already gives your Sonos speakers.
- **What stays on your Mac:** your Pressing Menu settings (appearance, launch at login, notifications, where to find Tracks). They're deleted with the app.
- **Notifications** are shown by macOS on your Mac only. Their cover image is downloaded from the address Shazam provides, as on the iPhone.
- **Spotify or Apple Music.** Right-clicking a Track opens a search for it in the service you chose, in its app or your browser. That service's privacy policy applies.

## Contact

Questions: open an issue at https://github.com/steffentchr/Pressing/issues.
