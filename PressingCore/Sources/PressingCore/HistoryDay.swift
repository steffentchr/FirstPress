import Foundation

/// The Plays that started on one day, under the day's header in History.
public struct HistoryDay: Sendable, Equatable, Identifiable {
    /// The start of the day, in the calendar's time zone.
    public var day: Date
    /// Newest first.
    public var plays: [Play]

    public var id: Date { day }

    public init(day: Date, plays: [Play]) {
        self.day = day
        self.plays = plays
    }

    /// Splits History into days. `plays` must be newest first, as
    /// `Pressing.history` is; the days come out newest first too.
    public static func days(of plays: [Play], calendar: Calendar = .current) -> [HistoryDay] {
        var days: [HistoryDay] = []
        for play in plays {
            let day = calendar.startOfDay(for: play.startedAt)
            if days.last?.day == day {
                days[days.count - 1].plays.append(play)
            } else {
                days.append(HistoryDay(day: day, plays: [play]))
            }
        }
        return days
    }
}
