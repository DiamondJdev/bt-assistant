import EventKit

/// The Sand Grid screens' calendar: EventKit events as `CalendarEvent`s.
extension CalendarStore: CalendarSource {
    public var hasAccess: Bool { access == .granted }

    public func events(in interval: DateInterval) -> [CalendarEvent] {
        ekEvents(from: interval.start, to: interval.end).map(CalendarEvent.init)
    }

    /// Updates the matching occurrence, or creates the event on the default calendar.
    public func save(_ event: CalendarEvent) throws -> CalendarEvent {
        let ek = find(event) ?? newEvent()
        if ek.calendar == nil { ek.calendar = defaultCalendar }
        guard ek.calendar != nil else { throw ToolError.failed("there is no default calendar") }
        event.apply(to: ek)
        do {
            try save(ek, span: .thisEvent)
        } catch {
            ek.rollback()
            throw error
        }
        // The saved object carries any new identifier EventKit gave the occurrence.
        return CalendarEvent(ek)
    }

    public func delete(_ event: CalendarEvent) throws {
        guard let ek = find(event) else { return }
        try delete(ek, span: .thisEvent)
    }

    private func find(_ event: CalendarEvent) -> EKEvent? {
        if let ek = CalendarEvent.eventKitID(event.id) {
            return self.event(identifier: ek.identifier, occurrenceStart: ek.occurrenceStart)
        }
        // BT's own events keep their id in the URL. ponytail: looks a month either side of the new time.
        let month: TimeInterval = 31 * 24 * 3600
        return ekEvents(from: event.start - month, to: event.end + month).first { BTEventLink($0.url)?.id == event.id }
    }
}

extension CalendarEvent {
    init(_ ek: EKEvent) {
        self.init(ek, source: Self.source(accountTitle: ek.calendar?.source?.title ?? ""))
    }

    /// BT's fields come from a `bt://event` URL; other events get an EventKit id and a guessed kind.
    init(_ ek: EKEvent, source: EventSource) {
        let link = BTEventLink(ek.url)
        let calendarTitle = ek.calendar?.title.lowercased() ?? ""
        self.init(
            id: link?.id ?? Self.eventKitID(identifier: ek.calendarItemIdentifier, occurrenceStart: ek.occurrenceDate ?? ek.startDate),
            title: ek.title ?? "",
            start: ek.startDate,
            end: ek.endDate,
            kind: link?.kind ?? (calendarTitle.contains("work") ? .work : .classSession),
            source: link?.id != nil ? .bt : source,
            location: ek.location.flatMap { $0.isEmpty ? nil : $0 },
            runAsFocus: link?.runAsFocus ?? false,
            focusPlan: link?.focusPlan,
            linkedProjectID: link?.projectID,
            isAllDay: ek.isAllDay,
            calendarTitle: ek.calendar?.title,
            hasAttendees: ek.hasAttendees,
            recurrenceSummary: Self.recurrenceSummary(ek.recurrenceRules ?? [])
        )
    }

    static func recurrenceSummary(_ rules: [EKRecurrenceRule]) -> String? {
        guard !rules.isEmpty else { return nil }
        return rules.map { rule in
            let interval = rule.interval
            switch rule.frequency {
            case .daily:
                return interval == 1 ? "Every day" : "Every \(interval) days"
            case .weekly:
                let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let days = (rule.daysOfTheWeek ?? []).map { names[$0.dayOfTheWeek.rawValue - 1] }
                let prefix = interval == 1 ? "Every" : "Every \(interval) weeks on"
                return days.isEmpty ? (interval == 1 ? "Every week" : "Every \(interval) weeks") : prefix + " " + days.joined(separator: ", ")
            case .monthly:
                return interval == 1 ? "Every month" : "Every \(interval) months"
            case .yearly:
                return interval == 1 ? "Every year" : "Every \(interval) years"
            @unknown default:
                return "Repeating event"
            }
        }.joined(separator: "; ")
    }

    /// Copies the event onto `ek`. A URL that isn't BT's (a meeting link) is never replaced.
    func apply(to ek: EKEvent) {
        ek.title = title
        ek.isAllDay = isAllDay
        ek.startDate = start
        ek.endDate = end
        ek.location = location
        guard ek.url == nil || ek.url?.scheme == BTEventLink.scheme else { return }
        let ownID = Self.eventKitID(id) == nil ? id : nil
        let link = BTEventLink(id: ownID, kind: kind, runAsFocus: runAsFocus, focusPlan: focusPlan, projectID: linkedProjectID)
        ek.url = ownID == nil && !runAsFocus && focusPlan == nil && linkedProjectID == nil ? nil : link.url
    }

    /// "ek:<calendarItemIdentifier>@<occurrence start>"
    static func eventKitID(identifier: String, occurrenceStart: Date) -> String {
        "ek:\(identifier)@\(occurrenceStart.timeIntervalSince1970)"
    }

    static func eventKitID(_ id: String) -> (identifier: String, occurrenceStart: Date)? {
        guard id.hasPrefix("ek:"), let at = id.lastIndex(of: "@"),
              let seconds = Double(id[id.index(after: at)...]) else { return nil }
        return (String(id[id.index(id.startIndex, offsetBy: 3)..<at]), Date(timeIntervalSince1970: seconds))
    }

    /// Google accounts in macOS Calendar are named after the Gmail address or "Google".
    static func source(accountTitle: String) -> EventSource {
        let title = accountTitle.lowercased()
        return title.contains("google") || title.contains("gmail") ? .google : .apple
    }
}

/// `bt://event?id=…&kind=…&focus=1&plan=…&project=…`, stored in `EKEvent.url`.
struct BTEventLink: Equatable {
    static let scheme = "bt"

    var id: String?
    var kind: EventKind?
    var runAsFocus: Bool
    var focusPlan: String?
    var projectID: String?

    init(id: String?, kind: EventKind?, runAsFocus: Bool, focusPlan: String?, projectID: String?) {
        self.id = id
        self.kind = kind
        self.runAsFocus = runAsFocus
        self.focusPlan = focusPlan
        self.projectID = projectID
    }

    init?(_ url: URL?) {
        guard let url, url.scheme == Self.scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        self.init(id: value("id"), kind: value("kind").flatMap(EventKind.init), runAsFocus: value("focus") == "1",
                  focusPlan: value("plan"), projectID: value("project"))
    }

    var url: URL? {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "event"
        c.queryItems = [
            id.map { URLQueryItem(name: "id", value: $0) },
            kind.map { URLQueryItem(name: "kind", value: $0.rawValue) },
            runAsFocus ? URLQueryItem(name: "focus", value: "1") : nil,
            focusPlan.map { URLQueryItem(name: "plan", value: $0) },
            projectID.map { URLQueryItem(name: "project", value: $0) },
        ].compactMap { $0 }
        return c.url
    }
}
