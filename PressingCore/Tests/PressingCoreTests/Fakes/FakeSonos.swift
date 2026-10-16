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
///
/// It behaves like the real thing as far as Pressing can see: joining with
/// `x-rincon:` moves a player into another group, `BecomeCoordinatorOfStandaloneGroup`
/// takes it out and hands the rest of its group to the next member, transport
/// commands sent to a group member fail with 800, and `GetTransportInfo` on a
/// member always says PLAYING.
@MainActor
final class FakeSonos {
    let network = FakeSonosNetwork()
    /// Zone groups, each led by its first player.
    private(set) var groups: [[FakeRoom]]
    /// What each group's coordinator plays, by the coordinator's RINCON id.
    private var sources: [String: (uri: String, state: String)] = [:]
    private var volumes: [String: Int] = [:]
    /// Hosts that refuse connections.
    var unreachable: Set<String> = []
    /// Hosts that answer every state-changing action with this UPnP fault code.
    var faults: [String: Int] = [:]
    /// Every request that broke the SOAP rules (wrong port, header or envelope).
    private(set) var malformed: [String] = []

    struct Unreachable: Error {}

    init(groups: [[FakeRoom]] = [[.livingRoom], [.kitchen], [.bridge]]) {
        self.groups = groups
        network.respond = { [unowned self] request in try self.answer(request) }
    }

    /// The commands a player received, in order: everything but reads (`Get…`).
    func calls(to room: FakeRoom, since mark: Int = 0) -> [SOAPCall] {
        requests(to: room, since: mark).filter { !$0.action.hasPrefix("Get") }
    }

    /// Every SOAP call a player received, reads and topology included.
    func requests(to room: FakeRoom, since mark: Int = 0) -> [SOAPCall] {
        network.requests
            .dropFirst(mark)
            .filter { $0.url.host == room.host }
            .compactMap(Self.parse)
    }

    /// A point in the request log, for `calls(to:since:)`.
    var mark: Int { network.requests.count }

    /// Every SOAP call any player received, including topology reads.
    var allCalls: [SOAPCall] { network.requests.compactMap(Self.parse) }

    func discover(_ room: FakeRoom) {
        network.discover(.found(SonosDevice(host: room.host)))
    }

    func lose(_ room: FakeRoom) {
        network.discover(.lost(SonosDevice(host: room.host)))
    }

    // MARK: - The household, as the Sonos app and the speakers see it

    /// The players grouped with this one, led by its coordinator.
    func group(of room: FakeRoom) -> [FakeRoom] {
        groups.first { $0.contains { $0.uuid == room.uuid } } ?? []
    }

    /// What the Room's group plays.
    func source(of room: FakeRoom) -> String { sources[coordinator(of: room).uuid]?.uri ?? "" }

    /// The transport state of the Room's group, as its coordinator reports it.
    func transportState(of room: FakeRoom) -> String { sources[coordinator(of: room).uuid]?.state ?? "STOPPED" }

    func volume(of room: FakeRoom) -> Int { volumes[room.uuid] ?? 20 }

    /// Someone plays something on the Room's group from the Sonos app.
    func play(_ uri: String, on room: FakeRoom, state: String = "PLAYING") {
        sources[coordinator(of: room).uuid] = (uri, state)
    }

    /// The Room's group stops, pauses or drops out without Pressing asking.
    func setTransportState(_ state: String, of room: FakeRoom) {
        sources[coordinator(of: room).uuid, default: ("", "STOPPED")].state = state
    }

    /// Someone pulls the Room out of its group in the Sonos app.
    func ungroup(_ room: FakeRoom) {
        leaveGroup(room)
    }

    /// Someone turns the Room up or down in the Sonos app or with its buttons.
    func pressVolume(_ volume: Int, on room: FakeRoom) {
        volumes[room.uuid] = volume
    }

    private func coordinator(of room: FakeRoom) -> FakeRoom { group(of: room).first ?? room }

    private func room(at host: String) -> FakeRoom? {
        groups.joined().first { $0.host == host }
    }

    private func room(withID uuid: String) -> FakeRoom? {
        groups.joined().first { $0.uuid == uuid }
    }

    /// Takes the player out of its group. The rest of the group carries on
    /// under its next member; the player is left alone with nothing playing.
    private func leaveGroup(_ room: FakeRoom) {
        guard let index = groups.firstIndex(where: { $0.contains { $0.uuid == room.uuid } }) else { return }
        var group = groups[index]
        let wasCoordinator = group.first?.uuid == room.uuid
        group.removeAll { $0.uuid == room.uuid }
        let source = sources.removeValue(forKey: room.uuid)
        if group.isEmpty {
            groups.remove(at: index)
        } else {
            groups[index] = group
            if wasCoordinator, let source { sources[group[0].uuid] = source }
        }
        groups.append([room])
        sources[room.uuid] = ("", "STOPPED")
    }

    // MARK: - Answering

    private func answer(_ request: HTTPRequest) throws -> HTTPResponse {
        guard let host = request.url.host, !unreachable.contains(host) else { throw Unreachable() }
        check(request)
        guard let call = Self.parse(request), let player = room(at: host) else { return HTTPResponse(status: 500) }
        if let code = faults[host], !call.action.hasPrefix("Get") {
            return Self.fault(code)
        }
        let service = Self.service(of: call.action)
        let isCoordinator = coordinator(of: player).uuid == player.uuid
        switch call.action {
        case "GetZoneGroupState":
            return Self.response(service, call.action, body: "<ZoneGroupState>\(Self.escape(topologyXML))</ZoneGroupState>")
        case "GetMediaInfo":
            let uri = isCoordinator ? source(of: player) : "x-rincon:\(coordinator(of: player).uuid)"
            return Self.response(service, call.action, body: "<NrTracks>1</NrTracks><MediaDuration>NOT_IMPLEMENTED</MediaDuration><CurrentURI>\(Self.escape(uri))</CurrentURI><CurrentURIMetaData></CurrentURIMetaData><NextURI></NextURI><NextURIMetaData></NextURIMetaData><PlayMedium>NETWORK</PlayMedium><RecordMedium>NOT_IMPLEMENTED</RecordMedium><WriteStatus>NOT_IMPLEMENTED</WriteStatus>")
        case "GetTransportInfo":
            // A group member always says PLAYING, whatever its group does.
            let state = isCoordinator ? transportState(of: player) : "PLAYING"
            return Self.response(service, call.action, body: "<CurrentTransportState>\(state)</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>")
        case "GetVolume":
            return Self.response(service, call.action, body: "<CurrentVolume>\(volume(of: player))</CurrentVolume>")
        case "SetVolume":
            volumes[player.uuid] = Int(call.args["DesiredVolume"] ?? "") ?? volume(of: player)
        case "SetAVTransportURI":
            let uri = call.args["CurrentURI"] ?? ""
            if uri.hasPrefix("x-rincon:") {
                guard let leader = room(withID: String(uri.dropFirst("x-rincon:".count))) else { return Self.fault(701) }
                leaveGroup(player)
                groups.removeAll { $0 == [player] }
                sources.removeValue(forKey: player.uuid)
                if let index = groups.firstIndex(where: { $0.first?.uuid == leader.uuid }) {
                    groups[index].append(player)
                }
            } else {
                guard isCoordinator else { return Self.fault(800) }
                sources[player.uuid] = (uri, "STOPPED")
            }
        case "Play":
            guard isCoordinator else { return Self.fault(800) }
            guard !source(of: player).isEmpty else { return Self.fault(701) }
            setTransportState("PLAYING", of: player)
        case "Stop":
            guard isCoordinator else { return Self.fault(800) }
            setTransportState("STOPPED", of: player)
        case "BecomeCoordinatorOfStandaloneGroup":
            leaveGroup(player)
        default:
            return Self.fault(401)
        }
        return Self.response(service, call.action, body: "")
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

    private static func fault(_ code: Int) -> HTTPResponse {
        let xml = #"<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>\#(code)</errorCode></UPnPError></detail></s:Fault></s:Body></s:Envelope>"#
        return HTTPResponse(status: 500, headers: ["Connection": "close"], body: Data(xml.utf8))
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
    for _ in 0..<2_000 { await Task.yield() }
}
