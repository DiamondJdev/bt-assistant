import Foundation

/// One occurrence of a calendar event, copied out of EventKit for display and tools.
public struct CalendarEventItem: Identifiable, Equatable, Sendable {
    /// `eventIdentifier` plus the occurrence start, unique per occurrence.
    public let id: String
    /// `EKEvent.calendarItemIdentifier`, shared by every occurrence of a series.
    public let eventIdentifier: String
    public let occurrenceStart: Date
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let colorHex: String?
    public let location: String?
    public let isRecurring: Bool
    public let isEditable: Bool

    public init(
        eventIdentifier: String,
        occurrenceStart: Date,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarTitle: String,
        colorHex: String?,
        location: String?,
        isRecurring: Bool,
        isEditable: Bool
    ) {
        id = "\(eventIdentifier)@\(occurrenceStart.timeIntervalSinceReferenceDate)"
        self.eventIdentifier = eventIdentifier
        self.occurrenceStart = occurrenceStart
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.location = location
        self.isRecurring = isRecurring
        self.isEditable = isEditable
    }
}

/// Earliest timed event starting at or after `date`. All-day and in-progress events are not "next".
func nextEvent(in items: [CalendarEventItem], after date: Date) -> CalendarEventItem? {
    items
        .filter { !$0.isAllDay && $0.start >= date }
        .min { $0.start < $1.start }
}

/// Events overlapping `day`, split into the all-day strip and the timeline.
func items(_ items: [CalendarEventItem], on day: Date, calendar: Calendar) -> (allDay: [CalendarEventItem], timed: [CalendarEventItem]) {
    let interval = calendar.dateInterval(of: .day, for: day)!
    let overlapping = items
        .filter { $0.start < interval.end && ($0.end > interval.start || $0.start == interval.start) }
        .sorted { $0.start < $1.start }
    return (overlapping.filter(\.isAllDay), overlapping.filter { !$0.isAllDay })
}

func calendarSnapshot(items: [CalendarEventItem], now: Date, calendar: Calendar) -> String {
    let today = items.filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: now) }
    guard let next = nextEvent(in: today, after: now) else {
        return "Calendar: nothing else today."
    }
    let time = formattedTime(next.start, calendar: calendar)
    var text = "Calendar: next is \(next.title) at \(time) (in \(formattedDuration(next.start.timeIntervalSince(now)))), id \(next.eventIdentifier)"
    let more = today.filter { $0.start > next.start }.count
    if more > 0 {
        text += "; \(more) more \(more == 1 ? "event" : "events") today"
    }
    return text + "."
}

func formattedTime(_ date: Date, calendar: Calendar) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened)
    style.timeZone = calendar.timeZone
    style.calendar = calendar
    style.locale = calendar.locale ?? .current
    // The formatter puts a narrow no-break space before AM/PM; plain text reads better for the model.
    return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
}

/// `Xh Ym` or `Ym`, rounding up so an event 30 seconds away reads "in 1m".
func formattedDuration(_ interval: TimeInterval) -> String {
    let minutes = Int((interval / 60).rounded(.up))
    let hours = minutes / 60
    return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
}
