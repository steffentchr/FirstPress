import Foundation
import PressingCore

/// One Sonos player as the household's topology lists it.
struct FakeRoom: Hashable {
    var uuid: String
    var name: String
    var host: String
    var invisible = false
    var isBridge = false
    /// Surround and Sub satellites bonded to this player.
    var satellites: [FakeRoom] = []

    static let livingRoom = FakeRoom(uuid: "RINCON_000E58AAAAAA01400", name: "Living Room", host: "192.168.1.101")
    static let kitchen = FakeRoom(uuid: "RINCON_000E58BBBBBB01400", name: "Kitchen", host: "192.168.1.102")
    static let bathroom = FakeRoom(uuid: "RINCON_000E58DDDDDD01400", name: "Bathroom", host: "192.168.1.104")
    static let bridge = FakeRoom(uuid: "RINCON_000E58CCCCCC01400", name: "BRIDGE", host: "192.168.1.100", invisible: true, isBridge: true)
}

/// A SOAP action a fake Room received: its name and arguments.
struct SOAPCall: Equatable, CustomStringConvertible {
    var action: String
    var args: [String: String]

    init(_ action: String, _ args: [String: String] = [:]) {
        self.action = action
        self.args = args
    }

    var description: String { "\(action)\(args.isEmpty ? "" : " \(args)")" }
}

/// A Sonos household at the HTTP level. Each player answers SOAP on
/// `<host>:1400` and records what it was asked; the test checks those calls.
@MainActor
final class FakeSonos {
    let network = FakeSonosNetwork()
    /// Zone groups, each led by its first player.
    var groups: [[FakeRoom]]
    /// Hosts that refuse connections.
    var unreachable: Set<String> = []
    /// Every request that broke the SOAP rules (wrong port, header or envelope).
    private(set) var malformed: [String] = []

    struct Unreachable: Error {}

    init(groups: [[FakeRoom]] = [[.livingRoom], [.kitchen], [.bridge]]) {
        self.groups = groups
        network.respond = { [unowned self] request in try self.answer(request) }
    }

    /// The SOAP calls a player received, in order, excluding topology reads.
    func calls(to room: FakeRoom) -> [SOAPCall] {
        network.requests
            .filter { $0.url.host == room.host }
            .compactMap(Self.parse)
            .filter { $0.action != "GetZoneGroupState" }
    }

    /// Every SOAP call any player received, including topology reads.
    var allCalls: [SOAPCall] { network.requests.compactMap(Self.parse) }

    func discover(_ room: FakeRoom) {
        network.discover(.found(SonosDevice(host: room.host)))
    }

    // MARK: - Answering

    private func answer(_ request: HTTPRequest) throws -> HTTPResponse {
        guard let host = request.url.host, !unreachable.contains(host) else { throw Unreachable() }
        check(request)
        guard let call = Self.parse(request) else { return HTTPResponse(status: 500) }
        switch call.action {
        case "GetZoneGroupState":
            return Self.response("ZoneGroupTopology", "GetZoneGroupState", body: "<ZoneGroupState>\(Self.escape(topologyXML))</ZoneGroupState>")
        default:
            return Self.response(Self.service(of: call.action), call.action, body: "")
        }
    }

    private func check(_ request: HTTPRequest) {
        let call = Self.parse(request)
        let service = call.map { Self.service(of: $0.action) } ?? "?"
        let expectedPath = service == "ZoneGroupTopology" ? "/ZoneGroupTopology/Control" : "/MediaRenderer/\(service)/Control"
        let expectedAction = "\"urn:schemas-upnp-org:service:\(service):1#\(call?.action ?? "?")\""
        if request.method != "POST" { malformed.append("method \(request.method)") }
        if request.url.port != 1400 { malformed.append("port \(String(describing: request.url.port))") }
        if request.url.path != expectedPath { malformed.append("path \(request.url.path)") }
        if request.headers["SOAPACTION"] != expectedAction { malformed.append("SOAPACTION \(String(describing: request.headers["SOAPACTION"]))") }
        if request.headers["Content-Type"]?.hasPrefix("text/xml") != true { malformed.append("Content-Type") }
    }

    private static func service(of action: String) -> String {
        switch action {
        case "GetZoneGroupState": "ZoneGroupTopology"
        case "GetVolume", "SetVolume": "RenderingControl"
        default: "AVTransport"
        }
    }

    private var topologyXML: String {
        let zoneGroups = groups.map { group in
            let members = group.map { member in
                let satellites = member.satellites.map { satellite in
                    #"<Satellite UUID="\#(satellite.uuid)" Location="http://\#(satellite.host):1400/xml/device_description.xml" ZoneName="\#(satellite.name)" Invisible="1"/>"#
                }.joined()
                return #"<ZoneGroupMember UUID="\#(member.uuid)" Location="http://\#(member.host):1400/xml/device_description.xml" ZoneName="\#(Self.escape(member.name))" SWGen="2" SSLPort="1443"\#(member.invisible ? #" Invisible="1""# : "")\#(member.isBridge ? #" IsZoneBridge="1""# : "")>\#(satellites)</ZoneGroupMember>"#
            }.joined()
            return #"<ZoneGroup Coordinator="\#(group[0].uuid)" ID="\#(group[0].uuid):42">\#(members)</ZoneGroup>"#
        }.joined()
        return "<ZoneGroupState><ZoneGroups>\(zoneGroups)</ZoneGroups><VanishedDevices/></ZoneGroupState>"
    }

    private static func response(_ service: String, _ action: String, body: String) -> HTTPResponse {
        let xml = #"<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\#(action)Response xmlns:u="urn:schemas-upnp-org:service:\#(service):1">\#(body)</u:\#(action)Response></s:Body></s:Envelope>"#
        return HTTPResponse(status: 200, headers: ["Connection": "close"], body: Data(xml.utf8))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Parsing requests

    /// Reads the action element out of a SOAP envelope, with its arguments unescaped.
    static func parse(_ request: HTTPRequest) -> SOAPCall? {
        let reader = EnvelopeReader()
        let parser = XMLParser(data: request.body)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse(), let action = reader.action else { return nil }
        return SOAPCall(action, reader.args)
    }

    private final class EnvelopeReader: NSObject, XMLParserDelegate {
        var action: String?
        var args: [String: String] = [:]
        private var path: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            if path.count == 3, path[0] == "Envelope", path[1] == "Body" { action = name }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if path.count == 4 { args[name] = text }
            path.removeLast()
        }
    }
}

/// Lets the core's pending Sonos requests run to completion.
@MainActor
func settle() async {
    for _ in 0..<200 { await Task.yield() }
}
