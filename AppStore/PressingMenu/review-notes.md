# Notes for App Review

Paste into App Store Connect › App Review Information › Notes. No sign-in is needed.

---

Pressing Menu is a menu-bar remote for Pressing, our iPhone app that streams a record playing on a USB turntable to Sonos speakers. Pressing Menu shows what Pressing is playing and switches its Rooms. It does nothing on its own: it needs Pressing open on an iPhone on the same Wi-Fi network as the Mac. You can see the two work together without a turntable or Sonos speakers:

1. On an iPhone on the same Wi-Fi network as the Mac, install Pressing (<ADD APP STORE OR TESTFLIGHT LINK BEFORE SUBMITTING>) and open it. On the start screen, choose "iPhone Microphone (picks up the room)" as the input, and allow microphone and local network access.
2. Open Pressing Menu on the Mac. Allow local network access and notifications when asked. It has no Dock icon: click the record in the menu bar to open the panel. It says "Looking for Pressing on your iPhone…", then "Waiting for a Record" once it has found the iPhone.
3. Play music aloud near the phone, from another device. The panel says "A Record is playing", and within about 30 seconds the Track's title and artist appear. Close the panel and let the next song play: a notification shows the new Track. Stop the music for 12 seconds and a "Flip the record" notification appears. Clicking a notification opens the panel.
4. In the panel's footer, click the summary on the right (it says "No Rooms" at first) to open the Rooms view. Tick "This iPhone": the phone plays the input through its speaker. With no Sonos speakers on the network, the Rooms list stays empty; that is expected.
5. Click the Track's title to search for it in Spotify. The gear opens Settings, where Apple Music can be chosen instead.
6. Close Pressing on the iPhone: the panel greys out and says "The iPhone can't be reached". Open it again and Pressing Menu reconnects by itself.

Local network access is used to find Pressing on the iPhone (Bonjour, _pressing._tcp) and talk to it directly. The power button in the panel's footer quits Pressing Menu and leaves Pressing on the iPhone playing.

A video of Pressing Menu controlling Pressing with a turntable and Sonos speakers: <ADD LINK BEFORE SUBMITTING>
