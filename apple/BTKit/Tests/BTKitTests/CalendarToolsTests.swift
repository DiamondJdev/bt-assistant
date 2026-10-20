import Foundation
import Testing
@testable import BTKit

@MainActor
struct CalendarToolsTests {
    let calendar = testCalendar()

    private func args<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decodeToolArguments(type, from: Data(json.utf8))
    }

    // MARK: Dates

    @Test func parsesOffsetZuluLocalAndBareDates() {
        #expect(parseToolDate("2026-10-21T15:00:00-05:00", calendar: calendar) == date(2026, 10, 21, 15))
        #expect(parseToolDate("2026-10-21T20:00:00Z", calendar: calendar) == date(2026, 10, 21, 15))
        #expect(parseToolDate("2026-10-21T20:00:00.000Z", calendar: calendar) == date(2026, 10, 21, 15))
        #expect(parseToolDate("2026-10-21T15:00:00", calendar: calendar) == date(2026, 10, 21, 15))
        #expect(parseToolDate("2026-10-21T15:30", calendar: calendar) == date(2026, 10, 21, 15, 30))
        #expect(parseToolDate("2026-10-21", calendar: calendar) == date(2026, 10, 21))
    }

    @Test func rejectsGarbageDates() {
        for text in ["", "tomorrow", "2026-13-40", "2026-10-21 at 3pm", "2026-10-21T15:00:00junk"] {
            #expect(parseToolDate(text, calendar: calendar) == nil, "\(text)")
        }
    }

    // MARK: Arguments

    @Test func decodesEachToolsArguments() throws {
        let list = try args(ListEventsArguments.self, #"{"start":"2026-10-21","end":"2026-10-22"}"#)
        #expect(list.start == "2026-10-21" && list.end == "2026-10-22")

        let create = try args(CreateEventArguments.self, #"""
            {"title":"Lab","start":"2026-10-21T15:00:00","duration_minutes":90,"calendar":"work","location":"Room 2","notes":"Bring goggles"}
            """#)
        #expect(create.title == "Lab" && create.durationMinutes == 90 && create.calendar == "work")
        #expect(create.end == nil && create.location == "Room 2" && create.notes == "Bring goggles")

        let update = try args(UpdateEventArguments.self, #"""
            {"id":"E1","occurrence_start":"2026-10-21T15:00:00-05:00","span":"future_events","title":"Lab 2"}
            """#)
        #expect(update.id == "E1" && update.occurrenceStart == "2026-10-21T15:00:00-05:00")
        #expect(update.span == .futureEvents && update.title == "Lab 2" && update.start == nil)

        let delete = try args(DeleteEventArguments.self, #"{"id":"E1","occurrence_start":"2026-10-21T15:00:00"}"#)
        #expect(delete.id == "E1" && delete.span == nil)
    }

    @Test func badArgumentsNameTheField() {
        #expect(throws: ToolError.badArguments("span is invalid.")) {
            try args(DeleteEventArguments.self, #"{"id":"E1","occurrence_start":"2026-10-21","span":"all_events"}"#)
        }
        #expect(throws: ToolError.badArguments("occurrence_start is missing.")) {
            try args(DeleteEventArguments.self, #"{"id":"E1"}"#)
        }
        #expect(throws: ToolError.badArguments("duration_minutes is invalid.")) {
            try args(CreateEventArguments.self, #"{"title":"Lab","start":"2026-10-21","duration_minutes":"long"}"#)
        }
    }

    // MARK: Ranges

    @Test func listRangeCapsAt31DaysAndBareEndDateIsInclusive() throws {
        let capped = try listRange(start: "2026-10-01", end: "2026-12-31", calendar: calendar)
        #expect(capped == DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1)))

        let oneDay = try listRange(start: "2026-10-21", end: "2026-10-21", calendar: calendar)
        #expect(oneDay == DateInterval(start: date(2026, 10, 21), end: date(2026, 10, 22)))

        let timed = try listRange(start: "2026-10-21T09:00:00", end: "2026-10-21T12:00:00", calendar: calendar)
        #expect(timed == DateInterval(start: date(2026, 10, 21, 9), end: date(2026, 10, 21, 12)))

        #expect(throws: ToolError.badArguments("end must be after start.")) {
            try listRange(start: "2026-10-22T09:00:00", end: "2026-10-21T09:00:00", calendar: calendar)
        }
        #expect(throws: ToolError.badArguments("start is not an ISO 8601 date: soon.")) {
            try listRange(start: "soon", end: "2026-10-21", calendar: calendar)
        }
    }

    @Test func createEndDefaultsToAnHour() throws {
        let start = date(2026, 10, 21, 15)
        #expect(try eventEnd(start: start, end: nil, durationMinutes: nil, calendar: calendar) == date(2026, 10, 21, 16))
        #expect(try eventEnd(start: start, end: nil, durationMinutes: 30, calendar: calendar) == date(2026, 10, 21, 15, 30))
        #expect(try eventEnd(start: start, end: "2026-10-21T17:00:00", durationMinutes: 30, calendar: calendar)
            == date(2026, 10, 21, 17))
        #expect(throws: ToolError.badArguments("end must be after start.")) {
            try eventEnd(start: start, end: "2026-10-21T14:00:00", durationMinutes: nil, calendar: calendar)
        }
        #expect(throws: ToolError.badArguments("duration_minutes must be at least 1.")) {
            try eventEnd(start: start, end: nil, durationMinutes: 0, calendar: calendar)
        }
    }

    // MARK: Lines

    @Test func lineCarriesWhatUpdateAndDeleteNeed() {
        let item = CalendarEventItem(
            eventIdentifier: "E1", occurrenceStart: date(2026, 10, 21, 15), title: "Lab",
            start: date(2026, 10, 21, 15, 30), end: date(2026, 10, 21, 16, 30), isAllDay: false,
            calendarTitle: "Work", colorHex: nil, location: "Room 2", isRecurring: true, isEditable: false
        )
        #expect(toolLine(item, calendar: calendar)
            == "Lab | id E1 | occurrence_start 2026-10-21T15:00:00-05:00 | 2026-10-21T15:30:00-05:00 to 2026-10-21T16:30:00-05:00 | calendar Work | location Room 2 | repeats | read-only")
        #expect(parseToolDate("2026-10-21T15:00:00-05:00", calendar: calendar) == item.occurrenceStart)
    }

    @Test func allDayLineShowsDaysAndSkipsEmptyExtras() {
        let item = CalendarEventItem(
            eventIdentifier: "E2", occurrenceStart: date(2026, 10, 21), title: "Trip",
            start: date(2026, 10, 21), end: date(2026, 10, 23), isAllDay: true,
            calendarTitle: "Home", colorHex: nil, location: nil, isRecurring: false, isEditable: true
        )
        #expect(toolLine(item, calendar: calendar)
            == "Trip | id E2 | occurrence_start 2026-10-21T00:00:00-05:00 | all day 2026-10-21 to 2026-10-22 | calendar Home")
    }

    // MARK: Module

    @Test func writesNeedApprovalAndSchemasAreClosed() {
        let tools = CalendarModule().tools
        #expect(tools.filter(\.needsApproval).map(\.name)
            == ["calendar_create_event", "calendar_update_event", "calendar_delete_event"])
        for tool in tools {
            guard case .object(let schema) = tool.parameters else { Issue.record("\(tool.name)"); continue }
            #expect(schema["additionalProperties"] == false)
            #expect(schema["required"] != nil)
        }
        guard case .object(let update) = tools[2].parameters, case .object(let properties)? = update["properties"] else {
            Issue.record("update schema")
            return
        }
        #expect(properties["span"] == ["type": "string", "enum": ["this_event", "future_events"],
                                       "description": "this_event (default) or future_events for a repeating event."])
    }

    @Test func toolsSayAccessIsOffWithoutAccess() async {
        let module = CalendarModule()
        #expect(module.store.access != .granted)
        await #expect(throws: ToolError.failed("Calendar access is off. Turn it on in System Settings, Privacy & Security, Calendars.")) {
            _ = try await module.call("calendar_list_events", arguments: Data(#"{"start":"2026-10-21","end":"2026-10-21"}"#.utf8))
        }
        await #expect(throws: ToolError.unknownTool("calendar_nope")) {
            _ = try await module.call("calendar_nope", arguments: Data("{}".utf8))
        }
    }
}
