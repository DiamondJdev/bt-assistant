import Foundation

enum CalWeekKind {
    case classSession, meeting, studyBlock, work, personal

    static func classify(_ event: CalendarEvent) -> Self {
        let title = event.title.lowercased()
        let calendar = event.calendarTitle?.lowercased() ?? ""
        if title.contains("office hours") || title.contains("meeting") || event.hasAttendees { return .meeting }
        if calendar.contains("uark") { return .classSession }
        if calendar == "bt" || calendar.contains("focus") || [.studyPlanned, .btDraft, .focusLogged].contains(event.kind) {
            return .studyBlock
        }
        if calendar.contains("work") { return .work }
        if event.calendarTitle == nil {
            return event.kind == .classSession ? .classSession : .work
        }
        return .personal
    }

    var label: String {
        switch self {
        case .classSession: "CLASS · UARK"
        case .meeting: "OFFICE HOURS · MEETING"
        case .studyBlock: "STUDY BLOCK · BT"
        case .work: "WORK"
        case .personal: "PERSONAL"
        }
    }
}

extension CalWeekLayout {
    static let gutter: CGFloat = 64
    static let hourHeight: CGFloat = 100
    static let gridHeight: CGFloat = 2400
    static let initialScroll: CGFloat = 900

    static func days(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: day), to: day)!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    static func weekTitle(_ date: Date, calendar: Calendar) -> String {
        let days = days(containing: date, calendar: calendar)
        let start = days[0], end = days[6]
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
        if !sameYear {
            return CalFormat.string(start, "MMMM d, yyyy", calendar) + " – " + CalFormat.string(end, "MMMM d, yyyy", calendar)
        }
        return CalFormat.string(start, "MMMM d", calendar) + " – " + CalFormat.string(end, sameMonth ? "d" : "MMMM d", calendar)
    }

    static func timed(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { !$0.isAllDay && $0.end >= $0.start }
    }

    static func events(on day: Date, in events: [CalendarEvent], calendar: Calendar) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return timed(events).filter {
            $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start))
        }
    }

    static func frame(_ event: CalendarEvent, on day: Date, calendar: Calendar) -> (y: CGFloat, height: CGFloat)? {
        let opening = calendar.startOfDay(for: day)
        let closing = calendar.date(byAdding: .day, value: 1, to: opening)!
        if event.start == event.end {
            guard event.start >= opening && event.start < closing else { return nil }
            return (min(y(event.start, calendar: calendar) + 1, gridHeight - 20), 20)
        }
        let start = max(event.start, opening), end = min(event.end, closing)
        guard start < end else { return nil }
        let top = y(start, calendar: calendar) + 1
        let bottom = end == closing ? gridHeight : y(end, calendar: calendar)
        return (top, min(gridHeight - top, max(20, bottom - top - 1)))
    }

    static func y(_ date: Date, calendar: Calendar) -> CGFloat {
        CGFloat(CalTimeline.hour(date, calendar)) * hourHeight
    }

    static func range(_ event: CalendarEvent, calendar: Calendar) -> String {
        let startPeriod = calendar.component(.hour, from: event.start) < 12 ? "AM" : "PM"
        if event.start == event.end { return time(event.start, calendar: calendar) + " " + startPeriod }
        let endPeriod = calendar.component(.hour, from: event.end) < 12 ? "AM" : "PM"
        return time(event.start, calendar: calendar) + (startPeriod == endPeriod ? "" : " " + startPeriod)
            + " – " + time(event.end, calendar: calendar) + " " + endPeriod
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        let hour = (calendar.component(.hour, from: date) + 11) % 12 + 1
        let minute = calendar.component(.minute, from: date)
        return minute == 0 ? "\(hour)" : String(format: "%d:%02d", hour, minute)
    }

    static func upcoming(_ events: [CalendarEvent], week: Date, now: Date, calendar: Calendar) -> [CalendarEvent] {
        let start = days(containing: week, calendar: calendar)[0]
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return Array(timed(events).filter { $0.start >= max(now, start) && $0.start < end }
            .sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }.prefix(8))
    }

    static func countdown(to date: Date, now: Date, calendar: Calendar) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        if minutes < 60 { return "IN \(minutes)M" }
        if minutes < 1440 { return "IN \(minutes / 60)H \(minutes % 60)M" }
        return CalFormat.string(date, "EEEE", calendar).uppercased()
    }

    static func conflicts(for event: CalendarEvent, in events: [CalendarEvent]) -> [CalendarEvent] {
        guard !event.isAllDay, event.kind != .deadline, event.end > event.start else { return [] }
        return timed(events).filter {
            $0.kind != .deadline && $0.end > $0.start && $0.id != event.id && $0.start < event.end && event.start < $0.end
        }
            .sorted { $0.start < $1.start }
    }

    static func conflictPrompt(for event: CalendarEvent, conflicts: [CalendarEvent], calendar: Calendar) -> String {
        let descriptions = ([event] + conflicts).map { item in
            "\(item.title) — \(CalFormat.string(item.start, "EEEE, MMMM d, yyyy", calendar)), \(range(item, calendar: calendar))" +
                (item.location.map { ", \($0)" } ?? "")
        }
        return "Help me resolve these overlapping calendar events. Suggest a schedule without changing anything until I approve:\n" + descriptions.joined(separator: "\n")
    }
}
