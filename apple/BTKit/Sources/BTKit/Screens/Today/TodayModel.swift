import Foundation

/// One `time · title · meta` row in the Today agenda.
struct AgendaRow: Identifiable, Equatable {
    var id: String
    var time: String
    var title: String
    var meta: String
    /// Accent time (NOW, booked block).
    var isHot = false
    /// Accent meta ("BOOKED BY BT").
    var isBooked = false
}

/// Today's code time, from `projects[].activity`.
struct CodeTimeSummary {
    static let goalSeconds: TimeInterval = 4 * 3600
    static let segments = 24

    /// Project name and seconds, largest first.
    var perProject: [(name: String, seconds: TimeInterval)]

    var total: TimeInterval { perProject.reduce(0) { $0 + $1.seconds } }
    var filledSegments: Int { min(Self.segments, Int((total / Self.goalSeconds * Double(Self.segments)).rounded())) }
    var percentOfGoal: Int { Int((total / Self.goalSeconds * 100).rounded()) }
    /// "3h 12m"
    var totalText: String { TodayFormat.duration(total, spaced: true) }
    /// "bt-client 1h48 · tariffninja 52m · mirai 32m"
    var breakdown: String { perProject.map { "\($0.name) \(TodayFormat.duration($0.seconds, spaced: false))" }.joined(separator: " · ") }
}

enum TodayFormat {
    static let ownerName = "Cameron"

    /// "1:30", 12-hour without AM/PM.
    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = (c.hour ?? 0) % 12
        return String(format: "%d:%02d", h == 0 ? 12 : h, c.minute ?? 0)
    }

    /// Spaced "3h 12m" or compact "1h48"; under an hour is "52m".
    static func duration(_ seconds: TimeInterval, spaced: Bool) -> String {
        let minutes = Int(seconds / 60)
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return spaced ? "\(h)h \(m)m" : String(format: "%dh%02d", h, m)
    }

    static func greeting(_ date: Date, _ calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case ..<12: "Morning"
        case ..<17: "Afternoon"
        default: "Evening"
        }
    }

    /// "Thu 22 Oct"
    static func dayLabel(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    /// "Fall · Week 9". Terms start the Monday of Jan 12, Jun 1 or Aug 24.
    // ponytail: fixed term start dates; read them from the school calendar when there is one.
    static func termLabel(_ date: Date, _ calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let (name, startMonth, startDay) = month >= 8 ? ("Fall", 8, 24) : month >= 6 ? ("Summer", 6, 1) : ("Spring", 1, 12)
        let anchor = calendar.date(from: DateComponents(year: year, month: startMonth, day: startDay))!
        let termWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        let weeks = calendar.dateComponents([.weekOfYear], from: termWeek, to: thisWeek).weekOfYear ?? 0
        return "\(name) · Week \(weeks + 1)"
    }

    /// "MATH 26103 · Discrete Math" → "Discrete Math".
    static func shortTitle(_ title: String) -> String {
        title.components(separatedBy: " · ").last ?? title
    }

    static func lowercasedFirst(_ s: String) -> String {
        s.prefix(1).lowercased() + s.dropFirst()
    }
}

extension AppStore {
    /// Booked block, if it still exists (Calendar may have deleted it).
    var todayBookedEvent: CalendarEvent? { today.bookedEventID.flatMap(event) }

    /// NOW row for the focus session, then events still to come today.
    var todayAgenda: [AgendaRow] {
        var rows: [AgendaRow] = []
        if focus.remainingSeconds > 0 {
            let title = focus.mode == .focus ? "Focus — \(TodayFormat.lowercasedFirst(focus.taskTitle))" : "Break"
            rows.append(AgendaRow(id: "now", time: "NOW", title: title, meta: "→ \(focus.clock)", isHot: true))
        }
        let upcoming = events(on: now).filter { $0.end > now && $0.kind != .focusLogged && $0.kind != .btDraft }
        for e in upcoming {
            let booked = e.id == today.bookedEventID
            let meta: String = switch e.kind {
            case .deadline: "BLACKBOARD"
            case _ where e.source == .bt: "BOOKED BY BT"
            default: e.location?.uppercased() ?? ""
            }
            rows.append(AgendaRow(
                id: e.id, time: TodayFormat.clock(e.start, calendar),
                title: e.kind == .deadline ? "\(e.title) due" : e.title,
                meta: meta, isHot: booked, isBooked: booked
            ))
        }
        return rows
    }

    var todayCodeTime: CodeTimeSummary {
        let dayStart = calendar.startOfDay(for: now)
        let perProject = projects.map { p in
            let seconds = p.activity.reduce(0.0) { sum, a in
                sum + max(0, min(a.end, now).timeIntervalSince(max(a.start, dayStart)))
            }
            return (name: p.name, seconds: seconds)
        }
        return CodeTimeSummary(perProject: perProject.filter { $0.seconds >= 60 }.sorted { $0.seconds > $1.seconds })
    }

    /// First free 50-minute slot today, 10 minutes after something ends ("Book 2:55").
    /// Nil when nothing fits before 11 PM.
    var todayBookingSlot: (start: Date, end: Date)? {
        let length: TimeInterval = 50 * 60, buffer: TimeInterval = 10 * 60
        let latestEnd = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
        let busy = events(on: now).filter { $0.kind != .deadline && $0.kind != .focusLogged }
        let fiveMinutes: TimeInterval = 300
        let soon = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / fiveMinutes).rounded(.up) * fiveMinutes)
        let candidates = ([soon] + busy.map { $0.end.addingTimeInterval(buffer) }).filter { $0 >= now }.sorted()
        // Prefer a slot after the next event, as BT suggests working until then.
        let after = nextEventToday.map { $0.end.addingTimeInterval(buffer) } ?? soon
        let start = candidates.first { start in
            start >= after && start.addingTimeInterval(length) <= latestEnd
                && !busy.contains { $0.start < start.addingTimeInterval(length) && start < $0.end }
        }
        return start.map { ($0, $0.addingTimeInterval(length)) }
    }

    /// The pre-booking BT sentence.
    var todayProposal: [Clause] {
        guard let slot = todayBookingSlot else {
            return [Clause("Today is full. "), Clause("Nothing free for another session before 11.", .muted)]
        }
        let session = Clause("session \(focus.number + 1) at \(TodayFormat.clock(slot.start, calendar)).", .accent)
        let task = "Finish the \(TodayFormat.lowercasedFirst(focus.taskTitle))"
        guard let next = nextEventToday else {
            return [Clause("Nothing else on your calendar today. "), Clause("\(task), and I’ll put", .muted), Clause(" "), session]
        }
        let minutes = max(0, Int(next.start.timeIntervalSince(now) / 60))
        let stop = TodayFormat.clock(next.start.addingTimeInterval(-10 * 60), calendar)
        return [
            Clause("You have \(minutes) \(minutes == 1 ? "minute" : "minutes") before \(TodayFormat.shortTitle(next.title)). "),
            Clause("\(task), stop at \(stop), and I’ll put", .muted), Clause(" "), session,
        ]
    }

    /// The confirmed BT sentence.
    func todayConfirmation(_ event: CalendarEvent) -> [Clause] {
        [
            Clause("Booked. "),
            Clause("Session \(focus.number + 1) is on your calendar at", .muted), Clause(" "),
            Clause("\(TodayFormat.clock(event.start, calendar)) – \(TodayFormat.clock(event.end, calendar))", .accent),
            Clause(", and Focus will start it for you.", .muted),
        ]
    }

    /// "Book 2:55": adds a Focus-linked study block and a ledger entry that undoes it.
    func bookTodaySession() {
        guard todayBookedEvent == nil, let slot = todayBookingSlot else { return }
        let event = CalendarEvent(
            title: "Focus — session \(focus.number + 1)", start: slot.start, end: slot.end,
            kind: .studyPlanned, source: .bt, runAsFocus: true, focusPlan: "50/10", linkedProjectID: focus.projectID
        )
        addEvent(event)
        let entry = LedgerEntry(
            time: now, kind: .calendar,
            summary: "Booked \(event.title) · \(TodayFormat.clock(slot.start, calendar))", undo: .removeEvent(id: event.id)
        )
        record(entry)
        today.bookedEventID = event.id
        today.bookedLedgerID = entry.id
    }

    func undoTodayBooking() {
        if let ledgerID = today.bookedLedgerID {
            undo(ledgerID)
        } else if let id = today.bookedEventID {
            deleteEvent(id)
        }
        today.bookedEventID = nil
        today.bookedLedgerID = nil
    }

    /// Composer send. Ignores blank text.
    func sendTodayDraft() {
        let text = today.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        today.sentThreadID = sendToBT(text)
        today.sentText = text
        today.draft = ""
    }
}
