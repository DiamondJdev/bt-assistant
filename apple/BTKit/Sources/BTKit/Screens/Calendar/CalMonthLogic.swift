import Foundation

enum CalMonthMath {
    static let studyGoalHours = 40.0
    static let tickCount = 40

    /// 0…1: booked hours on the day over the 8 AM–10 PM grid. Deadlines don't count.
    static func load(day: Date, events: [CalendarEvent], cal: Calendar) -> Double {
        let lo = cal.date(bySettingHour: Int(CalTimeline.startHour), minute: 0, second: 0, of: day)!
        let hi = cal.date(bySettingHour: Int(CalTimeline.endHour), minute: 0, second: 0, of: day)!
        let hours = events.filter { $0.kind != .deadline }.reduce(0.0) { sum, e in
            sum + max(0, min(e.end, hi).timeIntervalSince(max(e.start, lo))) / 3600
        }
        return min(1, hours / CalTimeline.span)
    }

    /// Study hours in the month: logged focus up to now, and planned/draft blocks still ahead.
    static func study(month: Date, now: Date, events: [CalendarEvent], cal: Calendar) -> (logged: Double, booked: Double) {
        let inMonth = events.filter { cal.isDate($0.start, equalTo: month, toGranularity: .month) }
        let logged = inMonth.filter { $0.kind == .focusLogged && $0.start <= now }.reduce(0) { $0 + $1.duration } / 3600
        let booked = inMonth.filter { ($0.kind == .studyPlanned || $0.kind == .btDraft) && $0.end > now }
            .reduce(0) { $0 + $1.duration } / 3600
        return (logged, booked)
    }

    /// Filled and dashed segments of the 40-tick bar (1 tick per hour of a 40h goal).
    static func ticks(logged: Double, booked: Double) -> (filled: Int, dashed: Int) {
        let perTick = studyGoalHours / Double(tickCount)
        let filled = min(tickCount, Int((logged / perTick).rounded()))
        let dashed = min(tickCount - filled, Int((booked / perTick).rounded()))
        return (filled, dashed)
    }

    /// Monday of next week.
    static func nextWeekStart(now: Date, cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: 7, to: CalDates.weekStart(now, cal))!
    }

    /// The four blocks BT drafts for next week ("around your shifts").
    static func lookAheadDrafts(now: Date, cal: Calendar) -> [CalendarEvent] {
        let monday = nextWeekStart(now: now, cal: cal)
        let plan: [(String, Int, Double, Double)] = [
            ("HW 7", 0, 19, 20), ("CHEM lab", 2, 19, 20), ("bt-client", 3, 14, 16), ("Review", 4, 16, 16.75),
        ]
        return plan.map { title, day, a, b in
            let d = cal.date(byAdding: .day, value: day, to: monday)!
            return CalendarEvent(
                title: title, start: d.addingTimeInterval(a * 3600), end: d.addingTimeInterval(b * 3600),
                kind: .btDraft, source: .bt, runAsFocus: true, focusPlan: "2×25"
            )
        }
    }

    /// Deadlines and study blocks in next Mon–Fri, for the look-ahead sentence.
    static func nextWeekCounts(now: Date, events: [CalendarEvent], cal: Calendar) -> (deadlines: Int, study: Int) {
        let monday = nextWeekStart(now: now, cal: cal)
        let saturday = cal.date(byAdding: .day, value: 5, to: monday)!
        let week = events.filter { $0.start >= monday && $0.start < saturday }
        return (week.filter { $0.kind == .deadline }.count, week.filter { $0.kind == .studyPlanned }.count)
    }

    /// Short label for a month cell or swatch row.
    static func itemTitle(_ e: CalendarEvent) -> String {
        switch e.kind {
        case .btDraft: "BT · " + e.title
        case .focusLogged: "Focus " + CalFormat.hours(e.duration / 3600)
        default: e.title
        }
    }
}
