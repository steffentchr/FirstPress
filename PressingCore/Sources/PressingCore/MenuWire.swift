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

    /// A Sonos Room as the phone's Rooms sheet lists it.
    public struct Room: Sendable, Equatable, Codable, Identifiable {
        /// The RINCON id of the Room's visible player.
        public var id: String
        public var name: String
        /// Switched on in Pressing: a Session takes it over.
        public var isOn: Bool
        /// 0 to 100.
        public var volume: Int
        public var isReachable: Bool
        /// Taken over in the Sonos app: Pressing stepped back from it.
        public var isSteppedBack: Bool

        public init(id: String, name: String, isOn: Bool, volume: Int, isReachable: Bool = true, isSteppedBack: Bool = false) {
            self.id = id
            self.name = name
            self.isOn = isOn
            self.volume = volume
            self.isReachable = isReachable
            self.isSteppedBack = isSteppedBack
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
    /// The Sonos Rooms found, by name. Added to version 1 after its first
    /// release: an older phone sends none.
    public var rooms: [Room]

    public init(major: Int = MenuSnapshot.currentMajor, page: Page, record: Record? = nil, track: Track? = nil, recentPlays: [Play] = [], rooms: [Room] = []) {
        self.major = major
        self.page = page
        self.record = record
        self.track = track
        self.recentPlays = recentPlays
        self.rooms = rooms
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        major = try container.decode(Int.self, forKey: .major)
        page = try container.decode(Page.self, forKey: .page)
        record = try container.decodeIfPresent(Record.self, forKey: .record)
        track = try container.decodeIfPresent(Track.self, forKey: .track)
        recentPlays = try container.decodeIfPresent([Play].self, forKey: .recentPlays) ?? []
        rooms = try container.decodeIfPresent([Room].self, forKey: .rooms) ?? []
    }
}

/// What a Pressing Menu asks of the phone: the same intents the phone's own
/// Rooms sheet sends.
public enum MenuCommand: Sendable, Equatable {
    /// Switch a Room on or off.
    case switchRoom(id: String, on: Bool)
    /// Set a Room's volume, 0 to 100.
    case setVolume(id: String, volume: Int)
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

    private struct CommandFields: Codable {
        var type: String
        var major: Int
        var id: String?
        var on: Bool?
        var volume: Int?
    }

    public static func encode(_ command: MenuCommand) -> Data {
        let fields = switch command {
        case .switchRoom(let id, let on):
            CommandFields(type: "switchRoom", major: MenuSnapshot.currentMajor, id: id, on: on)
        case .setVolume(let id, let volume):
            CommandFields(type: "setVolume", major: MenuSnapshot.currentMajor, id: id, volume: volume)
        }
        return try! encoder.encode(fields)
    }

    /// A command from a Pressing Menu, as the phone reads it. Nil for one
    /// this build doesn't know, or from a newer major version.
    public static func decodeCommand(_ data: Data) -> MenuCommand? {
        guard let fields = try? decoder.decode(CommandFields.self, from: data),
              fields.major <= MenuSnapshot.currentMajor
        else { return nil }
        switch fields.type {
        case "switchRoom":
            guard let id = fields.id, let on = fields.on else { return nil }
            return .switchRoom(id: id, on: on)
        case "setVolume":
            guard let id = fields.id, let volume = fields.volume else { return nil }
            return .setVolume(id: id, volume: volume)
        default:
            return nil
        }
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
