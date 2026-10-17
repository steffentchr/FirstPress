import Foundation

/// A Sonos device found on the network. Room names and grouping come from
/// ZoneGroupTopology once any one device is found (ADR-0003).
public struct SonosDevice: Sendable, Hashable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int = 1400) {
        self.host = host
        self.port = port
    }
}

public enum SonosDiscoveryEvent: Sendable, Equatable {
    case found(SonosDevice)
    case lost(SonosDevice)
}

/// Port: finding Sonos devices and talking SOAP-over-HTTP to `<ip>:1400`.
///
/// Production: `NWBrowser` on `_sonos._tcp` plus URLSession (ADR-0001,
/// ADR-0003). Envelopes are built and parsed in the core, so the fake works
/// at the HTTP level.
@MainActor
public protocol SonosNetwork: AnyObject {
    func setDiscoveryHandler(_ handler: @escaping @MainActor (SonosDiscoveryEvent) -> Void)
    func startDiscovery()
    func stopDiscovery()
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
