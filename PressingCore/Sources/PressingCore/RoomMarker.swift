/// Why a switched-on Room may be quiet, as both the phone's Rooms sheet and
/// Pressing Menu's Rooms view mark it: decided once, here.
public enum RoomMarker: Sendable, Equatable {
    /// The Room stopped answering.
    case cantBeReached
    /// Someone took it over in the Sonos app, so Pressing stepped back:
    /// switching it off and on takes it back.
    case takenOverInSonosApp

    /// Can't be reached wins over taken over: a Room that doesn't answer
    /// can't be taken back either.
    init?(isReachable: Bool, isSteppedBack: Bool) {
        if !isReachable { self = .cantBeReached } else if isSteppedBack { self = .takenOverInSonosApp } else { return nil }
    }

    /// The words beneath the Room's name.
    public var text: String {
        switch self {
        case .cantBeReached: "Can't be reached"
        case .takenOverInSonosApp: "Taken over in the Sonos app. Switch off and on to take it back."
        }
    }

    /// The SF Symbol shown with them.
    public var symbolName: String {
        switch self {
        case .cantBeReached: "wifi.exclamationmark"
        case .takenOverInSonosApp: "hand.raised"
        }
    }
}

extension RoomState {
    /// The marker the phone's Rooms sheet shows.
    public var marker: RoomMarker? {
        RoomMarker(isReachable: isReachable, isSteppedBack: isSteppedBack)
    }
}

extension MenuSnapshot.Room {
    /// The marker Pressing Menu's Rooms view shows, as the phone shows it.
    public var marker: RoomMarker? {
        RoomMarker(isReachable: isReachable, isSteppedBack: isSteppedBack)
    }
}
