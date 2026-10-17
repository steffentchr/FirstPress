# Local UPnP for Sonos control, not the official Control API

First Press controls Rooms over Sonos's local UPnP/SOAP interface on port 1400 (AVTransport, RenderingControl, ZoneGroupTopology). The official Sonos Control API needs OAuth, a cloud round trip for every command and a Sonos developer integration, all for a phone that sits on the same LAN as the speakers. The local interface is unofficial but has been stable for years, and SoCo and node-sonos-http-api rely on it.

## Consequences

Sonos could change or remove the local interface in a firmware update without notice. If that happens, the official API is the fallback, at the cost of OAuth and cloud latency.
