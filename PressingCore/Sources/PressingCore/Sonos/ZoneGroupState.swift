import Foundation

/// A Room as ZoneGroupTopology lists it.
struct TopologyRoom: Equatable {
    /// The RINCON id of the Room's visible player.
    var id: RoomState.ID
    var name: String
    /// Where its SOAP interface is, on port 1400.
    var host: String
    /// The RINCON id of the player leading its Sonos group.
    var coordinator: RoomState.ID
}

/// Reads the Rooms out of `GetZoneGroupState`.
///
/// Only `ZoneGroupMember` elements are players a listener sees. Members
/// marked `Invisible="1"` (the second speaker of a stereo pair) or
/// `IsZoneBridge="1"` are skipped, and `Satellite` elements (surrounds, Sub)
/// are never members, so each Room appears once.
enum ZoneGroupState {
    static func rooms(in xml: String) -> [TopologyRoom] {
        let reader = Reader()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        parser.parse()
        return reader.rooms
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var rooms: [TopologyRoom] = []
        private var coordinator = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "ZoneGroup":
                coordinator = attributes["Coordinator"] ?? ""
            case "ZoneGroupMember":
                guard attributes["Invisible"] != "1", attributes["IsZoneBridge"] != "1",
                      let id = attributes["UUID"], let name = attributes["ZoneName"],
                      let host = attributes["Location"].flatMap({ URLComponents(string: $0)?.host })
                else { return }
                rooms.append(TopologyRoom(id: id, name: name, host: host, coordinator: coordinator))
            default:
                break
            }
        }
    }
}
