import Foundation

/// BT's drafted block on Day, re-drafted from the "Tell BT" input.
struct CalDayDraft: Equatable {
    static let defaultPrompt = "1h CHEM lab report after SI"
    static let bufferMinutes = 15.0

    var title: String
    var start: Date
    var end: Date
    var focusPlan: String
    var focusText: String
    var why: String

    /// The mockup's simple parse: a leading duration ("1h", "45m"), the title, and an optional
    /// "after <event>" anchor that starts 15 min after that event on `day` ends.
    static func parse(_ input: String, day: Date, now: Date, events: [CalendarEvent], cal: Calendar) -> CalDayDraft {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var minutes = 60.0
        if let m = text.firstMatch(of: /^(\d+(?:\.\d+)?)\s*(h|hours?|m|mins?|minutes?)\b\s*/.ignoresCase()) {
            let n = Double(m.1) ?? 1
            minutes = m.2.lowercased().hasPrefix("h") ? n * 60 : n
            text.removeSubrange(m.range)
        }
        minutes = min(max(minutes, 15), 8 * 60)

        var anchor: String?
        if let m = text.firstMatch(of: /\s+(after|before|at|on)\s+(.*)$/.ignoresCase()) {
            if m.1.lowercased() == "after" { anchor = String(m.2).trimmingCharacters(in: .whitespaces) }
            text.removeSubrange(m.range)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let title = text.isEmpty ? "Study block" : text.prefix(1).uppercased() + text.dropFirst()

        let dayEvents = events.filter { cal.isDate($0.start, inSameDayAs: day) && $0.kind != .deadline && $0.kind != .focusLogged }
        let after = anchor.flatMap { a in dayEvents.sorted { $0.start < $1.start }.first { words($0.title).isSuperset(of: words(a)) } }
        let start: Date
        let why: String
        if let after {
            start = after.end.addingTimeInterval(bufferMinutes * 60)
            why = "15 min buffer after \(anchor ?? after.title)"
        } else {
            start = firstOpening(day: day, now: now, events: dayEvents, minutes: minutes, cal: cal)
            why = "First open time that day"
        }
        let sessions = max(1, Int(minutes / 30))
        return CalDayDraft(
            title: title, start: start, end: start.addingTimeInterval(minutes * 60),
            focusPlan: "\(sessions)×25",
            focusText: sessions == 1 ? "1 × 25" : "\(sessions) × 25 with a 5 min break",
            why: why
        )
    }

    private static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Earliest quarter hour from 8 AM (or now) with `minutes` free before 11 PM.
    private static func firstOpening(day: Date, now: Date, events: [CalendarEvent], minutes: Double, cal: Calendar) -> Date {
        let open = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let earliest = cal.isDate(day, inSameDayAs: now) ? max(open, now) : open
        var t = earliest
        let q = 15.0 * 60
        t = Date(timeIntervalSinceReferenceDate: (t.timeIntervalSinceReferenceDate / q).rounded(.up) * q)
        let bed = cal.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
        while t.addingTimeInterval(minutes * 60) <= bed {
            let end = t.addingTimeInterval(minutes * 60)
            guard let clash = events.first(where: { $0.start < end && $0.end > t }) else { return t }
            t = clash.end
        }
        return earliest
    }
}

/// One row of the Day agenda.
enum CalDayRow: Identifiable, Equatable {
    case event(CalendarEvent, isPast: Bool)
    case now
    case gap(start: Date, hours: Double)
    case due(CalendarEvent)

    var id: String {
        switch self {
        case .event(let e, _): e.id
        case .now: "now"
        case .gap: "gap"
        case .due(let e): "due-" + e.id
        }
    }

    static let bedHour = 23

    /// Timed events in order, the NOW band at the current time (today only),
    /// the open gap from the last block to bed, and deadlines.
    static func rows(day: Date, now: Date, events: [CalendarEvent], cal: Calendar) -> [CalDayRow] {
        let dayEvents = events.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        var timed: [(Date, CalDayRow)] = dayEvents.map { e in
            (e.start, e.kind == .deadline ? .due(e) : .event(e, isPast: e.end <= now))
        }
        if cal.isDate(day, inSameDayAs: now) { timed.append((now, .now)) }
        if let gap = gap(day: day, now: now, events: dayEvents, cal: cal) {
            timed.append((gap.start, .gap(start: gap.start, hours: gap.hours)))
        }
        // Stable: NOW sorts after blocks that started at the same moment.
        return timed.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
        }.map(\.element.1)
    }

    /// Free time from the end of the last block (or now) until bed, if at least 30 min.
    static func gap(day: Date, now: Date, events: [CalendarEvent], cal: Calendar) -> (start: Date, hours: Double)? {
        let bed = cal.date(bySettingHour: bedHour, minute: 0, second: 0, of: day)!
        let lastEnd = events.filter { $0.kind != .deadline && $0.kind != .focusLogged }.map(\.end).max() ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let start = max(lastEnd, cal.isDate(day, inSameDayAs: now) ? now : lastEnd)
        let hours = bed.timeIntervalSince(start) / 3600
        return hours >= 0.5 ? (start, hours) : nil
    }
}

struct CalDaySections {
    var earlier: [CalDayRow] = []
    var upcoming: [CalDayRow] = []
    var deadlines: [CalendarEvent] = []

    init(day: Date, now: Date, events: [CalendarEvent], cal: Calendar) {
        let today = cal.isDate(day, inSameDayAs: now)
        for row in CalDayRow.rows(day: day, now: now, events: events, cal: cal) {
            switch row {
            case let .due(event): deadlines.append(event)
            case .event(_, isPast: true) where today: earlier.append(row)
            default: upcoming.append(row)
            }
        }
    }
}

/// Today's hours inside 9 AM–11 PM, by kind.
struct CalHoursBreakdown: Equatable {
    static let windowStart = 9, windowEnd = 23

    var classHours = 0.0
    var focusHours = 0.0
    var otherHours = 0.0

    var total: Double { Double(Self.windowEnd - Self.windowStart) }
    var openHours: Double { max(0, total - classHours - focusHours - otherHours) }

    init(day: Date, events: [CalendarEvent], cal: Calendar) {
        let lo = cal.date(bySettingHour: Self.windowStart, minute: 0, second: 0, of: day)!
        let hi = cal.date(bySettingHour: Self.windowEnd, minute: 0, second: 0, of: day)!
        for e in events where e.kind != .deadline && e.kind != .focusLogged {
            let h = max(0, min(e.end, hi).timeIntervalSince(max(e.start, lo))) / 3600
            switch e.kind {
            case .classSession: classHours += h
            case .studyPlanned, .btDraft, .focusLogged: focusHours += h
            case .work: otherHours += h
            case .deadline: break
            }
        }
    }
}

/// A deadline in "Due soon", with the study blocks booked for it.
struct CalDueSoon: Equatable, Identifiable {
    var deadline: CalendarEvent
    var booked: [CalendarEvent]
    var id: String { deadline.id }

    /// Upcoming deadlines, soonest first. A study block counts for a deadline when it's planned
    /// before it and shares its first word ("CHEM lab report" ↔ "CHEM review"). Drafts don't count.
    static func list(now: Date, events: [CalendarEvent], limit: Int = 3) -> [CalDueSoon] {
        events.filter { $0.kind == .deadline && $0.end >= now }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { d in
                let key = d.title.split(separator: " ").first.map(String.init) ?? d.title
                let booked = events.filter {
                    $0.kind == .studyPlanned && $0.start < d.start && $0.end > now
                        && ($0.linkedAssignmentID == d.id || $0.title.localizedCaseInsensitiveContains(key))
                }.sorted { $0.start < $1.start }
                return CalDueSoon(deadline: d, booked: booked)
            }
    }
}
