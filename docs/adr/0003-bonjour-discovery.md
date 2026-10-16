# Bonjour discovery, not SSDP

Pressing discovers Rooms with Bonjour (`NWBrowser` on `_sonos._tcp`) rather than the usual Sonos SSDP multicast. SSDP on iOS needs Apple's multicast networking entitlement, which has to be requested and justified. Bonjour needs only `NSBonjourServices` and the local network permission. Room names and grouping come from `ZoneGroupTopology` once any one device is found, so Bonjour only needs to find one.
