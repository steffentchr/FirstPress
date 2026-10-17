# Live 320 kbps MP3 stream, not lossless or AAC

First Press encodes the turntable to 320 kbps CBR MP3 with LAME and serves it as an endless HTTP radio stream (`x-rincon-mp3radio`). Endless WAV and FLAC streams are unreliable on Sonos, and whether Sonos plays AAC over the radio scheme was not confirmed. MP3 radio is the format Sonos handles most predictably, and it carries ICY titles. LAME has to be cross-compiled as a static arm64 iOS library.

## Considered Options

- WAV/FLAC: lossless, but Sonos buffers and drops endless streams unpredictably.
- AAC via the system encoder: no third-party library, but unconfirmed on the radio scheme.
