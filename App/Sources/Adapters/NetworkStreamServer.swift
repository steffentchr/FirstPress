import Foundation
import Network
import FirstPressCore

/// Production StreamSink: a small HTTP server on a Network.framework listener.
///
/// It reads each request's line and headers, reports the client to the core,
/// and writes what the core sends: a plain `HTTP/1.0 200 OK` with the core's
/// headers, then the body until either side closes. No Content-Length and no
/// chunked encoding, as radio clients expect. A client that falls more than
/// ~10 s behind is dropped rather than buffered without limit; Sonos reconnects.
@MainActor
final class NetworkStreamServer: StreamSink {
    private final class Client {
        let connection: NWConnection
        var request = Data()
        var isStreaming = false
        /// A HEAD request: headers only, no body.
        var headOnly = false
        var bytesInFlight = 0
        init(connection: NWConnection) { self.connection = connection }
    }

    /// About 10 s of 320 kbps audio.
    private static let maxBytesInFlight = 400_000
    private static let maxRequestBytes = 8_192

    private var listener: NWListener?
    private var handler: (@MainActor (StreamSinkEvent) -> Void)?
    private var clients: [Int: Client] = [:]
    private var nextID = 1

    var localAddress: String? { Self.wifiIPv4Address() }

    func setEventHandler(_ handler: @escaping @MainActor (StreamSinkEvent) -> Void) {
        self.handler = handler
    }

    func startListening(port: UInt16) throws {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { self.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stopListening() {
        listener?.cancel()
        listener = nil
        for id in clients.keys { close(StreamClientID(id)) }
    }

    func sendHeaders(_ headers: [String: String], to client: StreamClientID) {
        let lines = ["HTTP/1.0 200 OK"] + headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        write(Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8), to: client)
    }

    func send(_ bytes: Data, to client: StreamClientID) {
        guard clients[client.rawValue]?.headOnly == false else { return }
        write(bytes, to: client)
    }

    private func write(_ bytes: Data, to client: StreamClientID) {
        guard let entry = clients[client.rawValue] else { return }
        guard entry.bytesInFlight + bytes.count <= Self.maxBytesInFlight else {
            // Too slow to keep up: let it reconnect instead of buffering forever.
            disconnect(client.rawValue)
            return
        }
        entry.bytesInFlight += bytes.count
        let count = bytes.count
        entry.connection.send(content: bytes, completion: .contentProcessed { error in
            MainActor.assumeIsolated {
                self.clients[client.rawValue]?.bytesInFlight -= count
                if error != nil { self.disconnect(client.rawValue) }
            }
        })
    }

    func close(_ client: StreamClientID) {
        guard let entry = clients.removeValue(forKey: client.rawValue) else { return }
        entry.connection.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = nextID
        nextID += 1
        let client = Client(connection: connection)
        clients[id] = client
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self.disconnect(id) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receiveRequest(id)
    }

    private func receiveRequest(_ id: Int) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let client = self.clients[id], !client.isStreaming else { return }
                if let data { client.request.append(data) }
                if let end = client.request.range(of: Data("\r\n\r\n".utf8)) {
                    self.handleRequest(id, Data(client.request[..<end.lowerBound]))
                } else if error != nil || isComplete || client.request.count > Self.maxRequestBytes {
                    self.disconnect(id)
                } else {
                    self.receiveRequest(id)
                }
            }
        }
    }

    private func handleRequest(_ id: Int, _ head: Data) {
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            disconnect(id)
            return
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let path = String(parts[1].split(separator: "?", maxSplits: 1).first ?? "")
        clients[id]?.isStreaming = true
        clients[id]?.headOnly = parts[0] == "HEAD"
        handler?(.connected(StreamClientID(id), path: path, wantsMetadata: headers["icy-metadata"] == "1"))
        if let client = clients[id], client.headOnly {
            // Close once the headers have gone out.
            client.connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                MainActor.assumeIsolated { self.disconnect(id) }
            })
        }
    }

    private func disconnect(_ id: Int) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.connection.cancel()
        if client.isStreaming {
            handler?(.disconnected(StreamClientID(id)))
        }
    }

    // MARK: - Address

    /// The phone's IPv4 address on Wi-Fi (`en0`), which Rooms fetch the stream from.
    private static func wifiIPv4Address() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard String(cString: interface.ifa_name) == "en0",
                  let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}
