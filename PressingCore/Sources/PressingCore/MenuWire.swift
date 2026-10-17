import Foundation

/// What the phone tells a Pressing Menu: a full snapshot of what it shows,
/// sent on connect and again on every change to it (ADR-0004).
///
/// Versions are additive. The phone only ever adds fields; it never removes
/// or reinterprets one. `major` is bumped only for a breaking change, and a
/// Pressing Menu ignores fields it doesn't know.
public struct MenuSnapshot: Sendable, Equatable, Codable {
    /// The wire contract's major version that this build speaks.
    public static let currentMajor = 1

    public var major: Int
    /// The current Play's Track, nil while nothing is identified.
    public var track: Track?

    public init(major: Int = MenuSnapshot.currentMajor, track: Track? = nil) {
        self.major = major
        self.track = track
    }
}

/// The JSON on the wire, both ways.
public enum MenuWire {
    /// A message from the phone, as Pressing Menu reads it.
    public enum Message: Sendable, Equatable {
        case snapshot(MenuSnapshot)
        /// The phone speaks a newer major version than this build.
        case newerMajor(Int)
        /// Not a message this build knows. Ignored.
        case unknown
    }

    private struct Envelope: Codable {
        var type: String
        var major: Int
    }

    private struct Tagged: Encodable {
        var type = "snapshot"
        var snapshot: MenuSnapshot

        func encode(to encoder: any Encoder) throws {
            try snapshot.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
        }

        enum CodingKeys: String, CodingKey { case type }
    }

    public static func encode(_ snapshot: MenuSnapshot) -> Data {
        // Encoding plain values can't fail.
        try! encoder.encode(Tagged(snapshot: snapshot))
    }

    public static func decode(_ data: Data) -> Message {
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return .unknown }
        guard envelope.major <= MenuSnapshot.currentMajor else { return .newerMajor(envelope.major) }
        guard envelope.type == "snapshot", let snapshot = try? decoder.decode(MenuSnapshot.self, from: data) else {
            return .unknown
        }
        return .snapshot(snapshot)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
