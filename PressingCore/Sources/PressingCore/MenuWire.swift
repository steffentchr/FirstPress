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

    /// The phone's page, as `PressingState.page` names it.
    public enum Page: String, Sendable, Equatable, Codable {
        /// The phone asks for its input: none chosen, or not connected.
        case chooseInput
        /// The input is ready and no Session is running.
        case waiting
        /// A Session is running.
        case nowPlaying

        public init(from decoder: any Decoder) throws {
            // A page added later reads as waiting.
            self = Page(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .waiting
        }
    }

    /// What the current Record is doing, while a Session runs.
    public enum Record: String, Sendable, Equatable, Codable {
        case playing
        case gap
        case flipped

        public init(from decoder: any Decoder) throws {
            // A state added later reads as playing.
            self = Record(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .playing
        }
    }

    /// A Play as History lists it.
    public struct Play: Sendable, Equatable, Codable {
        public var track: Track
        public var startedAt: Date

        public init(track: Track, startedAt: Date) {
            self.track = track
            self.startedAt = startedAt
        }
    }

    /// How many Plays Pressing Menu lists.
    public static let recentPlaysLimit = 10

    public var major: Int
    public var page: Page
    /// Nil outside a Session.
    public var record: Record?
    /// The current Play's Track, nil while nothing is identified.
    public var track: Track?
    /// History by the phone's rule, at most 10: newest first, each Track
    /// once at its latest Play, and the current Play left out.
    public var recentPlays: [Play]

    public init(major: Int = MenuSnapshot.currentMajor, page: Page, record: Record? = nil, track: Track? = nil, recentPlays: [Play] = []) {
        self.major = major
        self.page = page
        self.record = record
        self.track = track
        self.recentPlays = recentPlays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        major = try container.decode(Int.self, forKey: .major)
        page = try container.decode(Page.self, forKey: .page)
        record = try container.decodeIfPresent(Record.self, forKey: .record)
        track = try container.decodeIfPresent(Track.self, forKey: .track)
        recentPlays = try container.decodeIfPresent([Play].self, forKey: .recentPlays) ?? []
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
