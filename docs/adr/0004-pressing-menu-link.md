# Pressing Menu finds the phone over Bonjour and links by WebSocket, with no pairing

Pressing on the iPhone advertises a Bonjour service, `_pressing._tcp`, and Pressing Menu on a Mac connects to the first one it finds. Bonjour is what Pressing already uses to find Sonos (ADR-0003): it needs only `NSBonjourServices` and the local network permission on each side, and the listener has nothing to type in.

The link is one WebSocket per Pressing Menu, carrying JSON both ways, on its own listener apart from the Sonos stream server (ADR-0002). The phone needs to push a snapshot whenever what Pressing Menu shows changes, and Pressing Menu needs to send commands back. A WebSocket gives both directions on one long-lived connection, and Network.framework serves it on iOS without a third-party library. The phone serves several Pressing Menus at once.

There is no pairing or authentication. Anyone on the home network can already control the Sonos speakers over UPnP (ADR-0001), so Pressing Menu trusts the home network in the same way, and reaching the phone from outside it is out of scope.

## Consequences

- The wire contract is versioned additively. The phone only adds fields, never removes or reinterprets one, and carries a major version bumped only for a breaking change. Pressing Menu ignores fields it doesn't know, and asks to be updated only when the phone's major version is newer. The two apps ship apart: the phone through TestFlight, Pressing Menu through the Mac App Store.
- The snapshot encoding, and Pressing Menu's connection states and view model, live in the PressingCore package, so the whole contract is tested without a network. The adapters on each side only move messages.
- Pressing Menu reaches the phone only while Pressing runs. When iOS suspends it, Pressing Menu says it's looking for Pressing on the iPhone and keeps trying.
- Any device on the home network can read what's playing and, once commands arrive, switch Rooms. If that ever matters, pairing is the fallback.

## Considered Options

- Plain HTTP polling: simpler, but late to show a new Track and wasteful while nothing changes.
- A raw TCP socket with our own framing: as capable, but we'd write the framing that WebSocket already defines.
- Multipeer Connectivity: finds peers by itself, but it is a heavier, opinionated stack and pairs badly with a sandboxed menu-bar app.
- Pairing with a code shown on the phone: safer, but adds setup for a home device on a network that already trusts its speakers.
