import Foundation

public enum CalendarViewMode: String, CaseIterable, Sendable {
    case day, week, month

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

func visibleInterval(for mode: CalendarViewMode, containing date: Date, calendar: Calendar) -> DateInterval {
    calendar.dateInterval(of: mode.component, for: date)!
}

func stepped(_ date: Date, by mode: CalendarViewMode, forward: Bool, calendar: Calendar) -> Date {
    calendar.date(byAdding: mode.component, value: forward ? 1 : -1, to: date)!
}

func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
    days(in: visibleInterval(for: .week, containing: date, calendar: calendar), calendar: calendar)
}

/// Whole weeks covering the month of `date`, starting on `calendar.firstWeekday`.
func monthGridDays(containing date: Date, calendar: Calendar) -> [Date] {
    let month = visibleInterval(for: .month, containing: date, calendar: calendar)
    let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)!
    let start = visibleInterval(for: .week, containing: month.start, calendar: calendar).start
    let end = visibleInterval(for: .week, containing: lastDay, calendar: calendar).end
    return days(in: DateInterval(start: start, end: end), calendar: calendar)
}

/// Minutes from local midnight by the wall clock, clamped to the day, so a DST day still
/// has 24 hour rows and 3 PM sits on the 3 PM row.
func minutesIntoDay(_ date: Date, day: Date, calendar: Calendar) -> Double {
    let interval = visibleInterval(for: .day, containing: day, calendar: calendar)
    if date <= interval.start { return 0 }
    if date >= interval.end { return 24 * 60 }
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return Double(parts.hour! * 60 + parts.minute!)
}

/// Start for a new event: the next quarter hour when `day` is today, otherwise 9 AM on `day`.
func defaultNewEventStart(on day: Date, now: Date, calendar: Calendar) -> Date {
    guard calendar.isDate(day, inSameDayAs: now) else {
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    }
    let parts = calendar.dateComponents([.hour, .minute], from: now)
    return slotStart(minutes: parts.hour! * 60 + parts.minute! + 15, day: day, calendar: calendar)
}

/// The quarter hour at or before `minutes` past local midnight on `day`.
func slotStart(minutes: Int, day: Date, calendar: Calendar) -> Date {
    let quarter = min(max(minutes, 0), 24 * 60 - 15) / 15 * 15
    return calendar.date(bySettingHour: quarter / 60, minute: quarter % 60, second: 0, of: day)!
}

private func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
    var result: [Date] = []
    var day = interval.start
    while day < interval.end {
        result.append(day)
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return result
}
