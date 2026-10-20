import Foundation

// Arguments, date parsing and result lines for the `calendar_*` tools. Pure, so they're unit tested;
// `CalendarModule.call` does the EventKit work.

extension EditSpan: Decodable {}

struct ListEventsArguments: Decodable {
    let start: String
    let end: String
}

struct CreateEventArguments: Decodable {
    let title: String
    let start: String
    let end: String?
    let durationMinutes: Int?
    let calendar: String?
    let location: String?
    let notes: String?
}

struct UpdateEventArguments: Decodable {
    let id: String
    let occurrenceStart: String
    let span: EditSpan?
    let title: String?
    let start: String?
    let end: String?
    let location: String?
    let notes: String?
}

struct DeleteEventArguments: Decodable {
    let id: String
    let occurrenceStart: String
    let span: EditSpan?
}

/// Decodes snake_case tool arguments, turning decoding errors into a `ToolError` the model can act on.
func decodeToolArguments<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
        return try decoder.decode(type, from: data)
    } catch DecodingError.keyNotFound(let key, let context) {
        throw ToolError.badArguments("\(fieldName(context.codingPath + [key])) is missing.")
    } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context),
            let DecodingError.dataCorrupted(context) {
        guard !context.codingPath.isEmpty else { throw ToolError.badArguments("arguments must be a JSON object.") }
        throw ToolError.badArguments("\(fieldName(context.codingPath)) is invalid.")
    }
}

/// The schema's snake_case name for a decoding path.
private func fieldName(_ path: [any CodingKey]) -> String {
    path.map { $0.stringValue.replacing(/[A-Z]/) { "_" + $0.output.lowercased() } }.joined(separator: ".")
}

/// ISO 8601 with an offset or `Z`, a date-time without one (local time), or a bare date (local midnight).
func parseToolDate(_ text: String, calendar: Calendar) -> Date? {
    for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        if let date = formatter.date(from: text) { return date }
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = calendar.timeZone
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) { return date }
    }
    return nil
}

func toolDate(_ text: String, field: String, calendar: Calendar) throws -> Date {
    guard let date = parseToolDate(text, calendar: calendar) else {
        throw ToolError.badArguments("\(field) is not an ISO 8601 date: \(text).")
    }
    return date
}

private func isBareDate(_ text: String) -> Bool {
    text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
}

/// The range for `calendar_list_events`, at most 31 days. A bare end date includes that whole day.
func listRange(start: String, end: String, calendar: Calendar) throws -> DateInterval {
    let from = try toolDate(start, field: "start", calendar: calendar)
    var to = try toolDate(end, field: "end", calendar: calendar)
    if isBareDate(end) { to = calendar.date(byAdding: .day, value: 1, to: to)! }
    guard to > from else { throw ToolError.badArguments("end must be after start.") }
    return DateInterval(start: from, end: min(to, calendar.date(byAdding: .day, value: 31, to: from)!))
}

/// `end` if given, otherwise `start` plus `durationMinutes`, otherwise an hour.
func eventEnd(start: Date, end: String?, durationMinutes: Int?, calendar: Calendar) throws -> Date {
    let result: Date
    if let end {
        result = try toolDate(end, field: "end", calendar: calendar)
    } else {
        let minutes = durationMinutes ?? 60
        guard minutes >= 1 else { throw ToolError.badArguments("duration_minutes must be at least 1.") }
        result = start.addingTimeInterval(TimeInterval(minutes * 60))
    }
    guard result > start else { throw ToolError.badArguments("end must be after start.") }
    return result
}

/// One event for the model. `id` and `occurrence_start` go straight back into update and delete.
func toolLine(_ item: CalendarEventItem, calendar: Calendar) -> String {
    let times: String
    if item.isAllDay {
        let first = isoString(item.start, calendar: calendar, dateOnly: true)
        // EventKit ends all-day events at the last day's end or the next midnight.
        let last = isoString(max(item.start, item.end.addingTimeInterval(-1)), calendar: calendar, dateOnly: true)
        times = first == last ? "all day \(first)" : "all day \(first) to \(last)"
    } else {
        times = "\(isoString(item.start, calendar: calendar)) to \(isoString(item.end, calendar: calendar))"
    }
    var parts = [item.title, "id \(item.eventIdentifier)", "occurrence_start \(isoString(item.occurrenceStart, calendar: calendar))",
                 times, "calendar \(item.calendarTitle)"]
    if let location = item.location { parts.append("location \(location)") }
    if item.isRecurring { parts.append("repeats") }
    if !item.isEditable { parts.append("read-only") }
    return parts.joined(separator: " | ")
}

func isoString(_ date: Date, calendar: Calendar, dateOnly: Bool = false) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.formatOptions = dateOnly ? [.withFullDate] : [.withInternetDateTime]
    return formatter.string(from: date)
}
