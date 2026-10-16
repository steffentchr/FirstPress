import Foundation

/// A Sonos UPnP service on port 1400 (ADR-0001).
enum SonosService: String {
    case avTransport = "AVTransport"
    case renderingControl = "RenderingControl"
    case zoneGroupTopology = "ZoneGroupTopology"

    var controlPath: String {
        switch self {
        case .zoneGroupTopology: "/ZoneGroupTopology/Control"
        default: "/MediaRenderer/\(rawValue)/Control"
        }
    }

    var urn: String { "urn:schemas-upnp-org:service:\(rawValue):1" }
}

enum SonosError: Error, Equatable {
    /// A UPnP fault: HTTP 500 with an error code, such as 800 "not a coordinator".
    case fault(code: Int?)
    /// Any other non-200 answer.
    case status(Int)
    /// A 200 whose body wasn't the expected SOAP response.
    case malformedResponse
}

/// Builds SOAP 1.1 requests and reads their responses.
enum SOAP {
    /// SOAP always goes to port 1400, whatever port Bonjour advertised.
    static let port = 1400

    static func request(host: String, _ service: SonosService, _ action: String, _ args: KeyValuePairs<String, String>) -> HTTPRequest {
        let arguments = args.map { "<\($0.key)>\(escape($0.value))</\($0.key)>" }.joined()
        let envelope = #"<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\#(action) xmlns:u="\#(service.urn)">\#(arguments)</u:\#(action)></s:Body></s:Envelope>"#
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = service.controlPath
        return HTTPRequest(
            method: "POST",
            url: components.url!,
            headers: [
                "Content-Type": #"text/xml; charset="utf-8""#,
                // The quotes are part of the value.
                "SOAPACTION": "\"\(service.urn)#\(action)\"",
            ],
            body: Data(envelope.utf8)
        )
    }

    /// The out-arguments of a response, by name, unescaped.
    static func outArguments(of response: HTTPResponse) throws(SonosError) -> [String: String] {
        let reader = EnvelopeReader()
        let parser = XMLParser(data: response.body)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        let parsed = parser.parse()
        guard response.status == 200 else {
            throw response.status == 500 ? .fault(code: reader.errorCode) : .status(response.status)
        }
        guard parsed, reader.sawBody else { throw .malformedResponse }
        return reader.arguments
    }

    /// Escapes text for an XML element or attribute.
    static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// Reads `Envelope/Body/<ActionResponse>/<arg>` and any fault's `errorCode`,
    /// by local name, ignoring namespaces.
    private final class EnvelopeReader: NSObject, XMLParserDelegate {
        var arguments: [String: String] = [:]
        var errorCode: Int?
        var sawBody = false
        private var path: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            if path == ["Envelope", "Body"] { sawBody = true }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if path.count == 4, path[0] == "Envelope", path[1] == "Body", path[2] != "Fault" {
                arguments[name] = text
            }
            if name == "errorCode" { errorCode = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            path.removeLast()
        }
    }
}
