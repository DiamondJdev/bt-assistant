import EventKit
import SwiftUI

@MainActor
@Observable
public final class CalendarModule: ToolModule {
    public let id = "calendar"
    public let name = "Calendar"
    public let symbol = "calendar"
    public let tools: [ToolDefinition] = [
        ToolDefinition(
            name: "calendar_list_events",
            description: "List events in a date range. Each result has its id, occurrence start, title, times, calendar, location, whether it repeats and whether it can be edited.",
            parameters: [
                "type": "object",
                "properties": [
                    "start": ["type": "string", "description": .string(dateHelp)],
                    "end": ["type": "string", "description": .string(dateHelp + " A bare date includes that whole day. At most 31 days after start.")],
                ],
                "required": ["start", "end"],
                "additionalProperties": false,
            ]
        ),
        ToolDefinition(
            name: "calendar_create_event",
            description: "Create an event with a title, start, end or duration, and optional calendar, location and notes.",
            parameters: [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "start": ["type": "string", "description": .string(dateHelp)],
                    "end": ["type": "string", "description": .string(dateHelp)],
                    "duration_minutes": ["type": "integer", "minimum": 1, "description": "Used when end is missing. Default 60."],
                    "calendar": ["type": "string", "description": "Calendar title. Default: the default calendar."],
                    "location": ["type": "string"],
                    "notes": ["type": "string"],
                ],
                "required": ["title", "start"],
                "additionalProperties": false,
            ],
            needsApproval: true
        ),
        ToolDefinition(
            name: "calendar_update_event",
            description: "Change an event by id and occurrence start. Span is this_event (default) or future_events for repeating events.",
            parameters: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "occurrence_start": ["type": "string", "description": "occurrence_start exactly as calendar_list_events gave it."],
                    "span": spanSchema,
                    "title": ["type": "string"],
                    "start": ["type": "string", "description": .string(dateHelp + " Keeps the duration unless end is given.")],
                    "end": ["type": "string", "description": .string(dateHelp)],
                    "location": ["type": "string", "description": "Empty clears it."],
                    "notes": ["type": "string", "description": "Empty clears them."],
                ],
                "required": ["id", "occurrence_start"],
                "additionalProperties": false,
            ],
            needsApproval: true
        ),
        ToolDefinition(
            name: "calendar_delete_event",
            description: "Delete an event by id and occurrence start. Span is this_event (default) or future_events for repeating events.",
            parameters: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "occurrence_start": ["type": "string", "description": "occurrence_start exactly as calendar_list_events gave it."],
                    "span": spanSchema,
                ],
                "required": ["id", "occurrence_start"],
                "additionalProperties": false,
            ],
            needsApproval: true
        ),
    ]

    public let store: CalendarStore
    @ObservationIgnored let now: @Sendable () -> Date
    var mode: CalendarViewMode = .day
    var focusDate: Date
    var editorRequest: EditorRequest?

    public init(store: CalendarStore = CalendarStore(), now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
        focusDate = now()
    }

    public var snapshot: String? {
        guard store.access == .granted else { return nil }
        let now = now()
        let today = visibleInterval(for: .day, containing: now, calendar: .current)
        return calendarSnapshot(items: store.events(from: today.start, to: today.end), now: now, calendar: .current)
    }

    public var content: AnyView {
        AnyView(CalendarView(module: self))
    }

    /// Events for the visible range. Reading `changeToken` makes views refresh on store changes.
    func visibleEvents() -> [CalendarEventItem] {
        _ = store.changeToken
        let calendar = Calendar.current
        let interval: DateInterval
        if mode == .month {
            let days = monthGridDays(containing: focusDate, calendar: calendar)
            interval = DateInterval(start: days.first!, end: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
        } else {
            interval = visibleInterval(for: mode, containing: focusDate, calendar: calendar)
        }
        return store.events(from: interval.start, to: interval.end)
    }
}

// MARK: Tools

extension CalendarModule {
    public func call(_ name: String, arguments: Data) async throws -> String {
        guard tools.contains(where: { $0.name == name }) else { throw ToolError.unknownTool(name) }
        guard store.access == .granted else {
            throw ToolError.failed("Calendar access is off. Turn it on in System Settings, Privacy & Security, Calendars.")
        }
        let calendar = Calendar.current
        switch name {
        case "calendar_list_events":
            return try listEvents(decodeToolArguments(ListEventsArguments.self, from: arguments), calendar: calendar)
        case "calendar_create_event":
            return try createEvent(decodeToolArguments(CreateEventArguments.self, from: arguments), calendar: calendar)
        case "calendar_update_event":
            return try updateEvent(decodeToolArguments(UpdateEventArguments.self, from: arguments), calendar: calendar)
        default:
            return try deleteEvent(decodeToolArguments(DeleteEventArguments.self, from: arguments), calendar: calendar)
        }
    }

    private func listEvents(_ args: ListEventsArguments, calendar: Calendar) throws -> String {
        let range = try listRange(start: args.start, end: args.end, calendar: calendar)
        let header = "Events from \(isoString(range.start, calendar: calendar)) to \(isoString(range.end, calendar: calendar)):"
        let items = store.events(from: range.start, to: range.end)
        guard !items.isEmpty else { return header + " none." }
        return ([header] + items.map { toolLine($0, calendar: calendar) }).joined(separator: "\n")
    }

    private func createEvent(_ args: CreateEventArguments, calendar: Calendar) throws -> String {
        let start = try toolDate(args.start, field: "start", calendar: calendar)
        let end = try eventEnd(start: start, end: args.end, durationMinutes: args.durationMinutes, calendar: calendar)
        let event = store.newEvent()
        event.calendar = try targetCalendar(named: args.calendar)
        event.title = args.title.isEmpty ? "New Event" : args.title
        event.startDate = start
        event.endDate = end
        event.location = args.location.flatMap { $0.isEmpty ? nil : $0 }
        event.notes = args.notes.flatMap { $0.isEmpty ? nil : $0 }
        try commit(event) { try store.save(event, span: .thisEvent) }
        return "Created: " + toolLine(CalendarEventItem(event), calendar: calendar)
    }

    private func updateEvent(_ args: UpdateEventArguments, calendar: Calendar) throws -> String {
        let event = try writableEvent(id: args.id, occurrenceStart: args.occurrenceStart, calendar: calendar)
        // Parse everything before touching the event so a bad date leaves it unchanged.
        let start = try args.start.map { try toolDate($0, field: "start", calendar: calendar) }
        let end = try args.end.map { try toolDate($0, field: "end", calendar: calendar) }
        let newStart = start ?? event.startDate!
        let newEnd = end ?? newStart.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))
        guard newEnd > newStart else { throw ToolError.badArguments("end must be after start.") }
        if let title = args.title { event.title = title.isEmpty ? "New Event" : title }
        event.startDate = newStart
        event.endDate = newEnd
        if let location = args.location { event.location = location.isEmpty ? nil : location }
        if let notes = args.notes { event.notes = notes.isEmpty ? nil : notes }
        try commit(event) { try store.save(event, span: args.span ?? .thisEvent) }
        // EventKit may give the saved occurrence a new identifier; the saved event object carries it.
        return "Updated: " + toolLine(CalendarEventItem(event), calendar: calendar)
    }

    private func deleteEvent(_ args: DeleteEventArguments, calendar: Calendar) throws -> String {
        let event = try writableEvent(id: args.id, occurrenceStart: args.occurrenceStart, calendar: calendar)
        let span = args.span ?? .thisEvent
        let title = event.title ?? ""
        let when = event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened)
        try commit(event) { try store.delete(event, span: span) }
        return "Deleted \(title) on \(when)\(span == .futureEvents ? " and the occurrences after it" : "")."
    }

    /// Finds the occurrence by identifier plus occurrence start, as AGENTS.md requires.
    private func writableEvent(id: String, occurrenceStart: String, calendar: Calendar) throws -> EKEvent {
        let occurrence = try toolDate(occurrenceStart, field: "occurrence_start", calendar: calendar)
        guard let event = store.event(identifier: id, occurrenceStart: occurrence) else {
            throw ToolError.failed("No event with id \(id) at \(occurrenceStart). List events again for current ids.")
        }
        guard event.calendar?.allowsContentModifications == true else {
            throw ToolError.failed("\(event.title ?? "That event") is on \(event.calendar?.title ?? "a calendar") which is read-only.")
        }
        return event
    }

    private func targetCalendar(named title: String?) throws -> EKCalendar {
        let writable = store.writableCalendars()
        let names = writable.map(\.title).joined(separator: ", ")
        guard let title else {
            guard let calendar = store.defaultCalendar else { throw ToolError.failed("There is no default calendar. Name one of: \(names).") }
            return calendar
        }
        guard let calendar = writable.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
            throw ToolError.failed("No writable calendar named \(title). Writable calendars: \(names).")
        }
        return calendar
    }

    private func commit(_ event: EKEvent, _ write: () throws -> Void) throws {
        do {
            try write()
        } catch {
            event.rollback()
            throw ToolError.failed("Calendar couldn't save the change: \(error.localizedDescription)")
        }
    }
}

private let dateHelp = "ISO 8601 date or date-time. Without an offset it is local time."
private let spanSchema: JSONValue = [
    "type": "string", "enum": ["this_event", "future_events"],
    "description": "this_event (default) or future_events for a repeating event.",
]
