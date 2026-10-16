import Foundation
import Network
import PressingCore

/// Production SonosNetwork: Bonjour on `_sonos._tcp` (ADR-0003) and SOAP over
/// URLSession (ADR-0001).
///
/// The player's IP comes from the TXT record's `location` key
/// (`http://<ip>:1400/xml/device_description.xml`). The SRV port is 1443, the
/// HTTPS API, so the endpoint is never resolved; SOAP always goes to 1400.
@MainActor
final class BonjourSonosNetwork: SonosNetwork {
    private var browser: NWBrowser?
    private var handler: (@MainActor (SonosDiscoveryEvent) -> Void)?
    private var known: [NWEndpoint: SonosDevice] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        // The first request may wait for the local network permission prompt.
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        // Sonos closes the connection after every response.
        configuration.httpShouldUsePipelining = false
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration)
    }

    func setDiscoveryHandler(_ handler: @escaping @MainActor (SonosDiscoveryEvent) -> Void) {
        self.handler = handler
    }

    func startDiscovery() {
        guard browser == nil else { return }
        // .bonjourWithTXTRecord: plain .bonjour returns no TXT metadata.
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: "local."), using: NWParameters())
        browser.browseResultsChangedHandler = { results, _ in
            MainActor.assumeIsolated { self.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        known = [:]
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = Dictionary(
            http.allHeaderFields.compactMap { key, value in (key as? String).map { ($0, "\(value)") } },
            uniquingKeysWith: { first, _ in first }
        )
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var current: [NWEndpoint: SonosDevice] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  let location = txt["location"],
                  let host = URLComponents(string: location)?.host
            else { continue }
            current[result.endpoint] = SonosDevice(host: host)
        }
        for (endpoint, device) in known where current[endpoint] == nil {
            handler?(.lost(device))
        }
        for (endpoint, device) in current where known[endpoint] != device {
            handler?(.found(device))
        }
        known = current
    }
}
