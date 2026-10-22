import Foundation

/// The Week grid's visible hours, 8 AM–10 PM, and block placement over them.
enum CalTimeline {
    static let startHour = 8.0
    static let endHour = 22.0
    static var span: Double { endHour - startHour }

    /// Hours since midnight, e.g. 14:30 → 14.5.
    static func hour(_ date: Date, _ cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// 0…1 fraction down the grid for a time of day (clamped).
    static func fraction(_ date: Date, _ cal: Calendar) -> Double {
        min(1, max(0, (hour(date, cal) - startHour) / span))
    }

    /// Top offset and height, in points, for a block in a column `height` tall.
    /// Blocks are clipped to the visible hours; `minHeight` keeps short blocks clickable.
    static func frame(start: Date, end: Date, height: CGFloat, cal: Calendar, minHeight: CGFloat = 18) -> (y: CGFloat, height: CGFloat) {
        let top = fraction(start, cal)
        let endsNextDay = !cal.isDate(start, inSameDayAs: end) && end > start
        let bottom = endsNextDay ? 1 : fraction(end, cal)
        let y = CGFloat(top) * height
        let h = max(minHeight, CGFloat(bottom - top) * height)
        return (min(y, max(0, height - h)), h)
    }

    /// Whether the time of day is inside the grid (for the "now" line).
    static func isVisible(_ date: Date, _ cal: Calendar) -> Bool {
        (startHour...endHour).contains(hour(date, cal))
    }
}

/// Week and month date math. Weeks start on the calendar's first weekday (Monday for `.bt`).
enum CalDates {
    static func weekStart(_ date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func weekDays(_ date: Date, _ cal: Calendar) -> [Date] {
        let start = weekStart(date, cal)
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    static func monthStart(_ date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Whole weeks covering the month: 35 days, or 42 when the month needs a sixth row.
    static func monthGrid(_ date: Date, _ cal: Calendar) -> [Date] {
        let first = monthStart(date, cal)
        let gridStart = weekStart(first, cal)
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = cal.dateComponents([.day], from: gridStart, to: first).day ?? 0
        let count = lead + days > 35 ? 42 : 35
        return (0..<count).map { cal.date(byAdding: .day, value: $0, to: gridStart)! }
    }

    /// Moves the shown date by one period of the mode.
    static func step(_ date: Date, mode: CalendarMode, by n: Int, _ cal: Calendar) -> Date {
        switch mode {
        case .day: cal.date(byAdding: .day, value: n, to: date)!
        case .week: cal.date(byAdding: .day, value: 7 * n, to: date)!
        case .month: cal.date(byAdding: .month, value: n, to: date)!
        }
    }

    /// Index 0–6 of `date` in its week.
    static func weekdayIndex(_ date: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: weekStart(date, cal), to: cal.startOfDay(for: date)).day ?? 0
    }
}

/// Text formats used across the three views.
enum CalFormat {
    /// "5:30" (12-hour, no suffix), like the mockups.
    static func time(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0
        return String(format: "%d:%02d", (h + 11) % 12 + 1, c.minute ?? 0)
    }

    static func range(_ start: Date, _ end: Date, _ cal: Calendar, separator: String = "–") -> String {
        time(start, cal) + separator + time(end, cal)
    }

    /// 4.75 → "4h 45m", 3 → "3h".
    static func hours(_ h: Double) -> String {
        let minutes = Int((h * 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func string(_ date: Date, _ format: String, _ cal: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }

    /// "Oct 19 – 25", or "Oct 26 – Nov 1" across months.
    static func span(_ first: Date, _ last: Date, _ cal: Calendar, separator: String = " – ") -> String {
        let sameMonth = cal.isDate(first, equalTo: last, toGranularity: .month)
        return string(first, "MMM d", cal) + separator + string(last, sameMonth ? "d" : "MMM d", cal)
    }

    /// Countdown to a deadline: "45m", "11h", "3d".
    static func countdown(from now: Date, to due: Date) -> String {
        let s = max(0, due.timeIntervalSince(now))
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    static func kindLabel(_ kind: EventKind) -> String {
        switch kind {
        case .classSession: "Class"
        case .work: "Work"
        case .focusLogged: "Focus logged"
        case .studyPlanned: "Study block"
        case .btDraft: "BT draft"
        case .deadline: "Due"
        }
    }

    /// "APPLE · CLASS"
    static func sourceLabel(_ event: CalendarEvent) -> String {
        let kind: String = switch event.kind {
        case .classSession: "Class"
        case .work: "Work"
        case .focusLogged: "Logged"
        case .studyPlanned: "Study"
        case .btDraft: "Draft"
        case .deadline: "Due"
        }
        return "\(event.source.rawValue) · \(kind)".uppercased()
    }
}

/// Popover placement beside a selected Week block: right of it, or flipped left for Fri–Sun.
enum CalPopover {
    static let width: CGFloat = 300
    static let estimatedHeight: CGFloat = 300

    static func flipsLeft(dayIndex: Int) -> Bool { dayIndex >= 4 }

    /// Leading x of the popover in a grid whose day columns start at `columnX` and are `columnWidth` wide.
    static func x(dayIndex: Int, columnX: (Int) -> CGFloat, columnWidth: CGFloat, gap: CGFloat = 4) -> CGFloat {
        flipsLeft(dayIndex: dayIndex)
            ? columnX(dayIndex) - width - gap
            : columnX(dayIndex) + columnWidth + gap
    }

    /// Top y: level with the block, kept inside the grid.
    static func y(blockY: CGFloat, gridHeight: CGFloat) -> CGFloat {
        max(0, min(blockY, gridHeight - estimatedHeight))
    }
}
