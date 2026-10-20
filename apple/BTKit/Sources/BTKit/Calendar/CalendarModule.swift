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
            description: "List events in a date range. Each result has its id, occurrence start, title, times, calendar, location, whether it repeats and whether it can be edited."
        ),
        ToolDefinition(
            name: "calendar_create_event",
            description: "Create an event with a title, start, end or duration, and optional calendar, location and notes."
        ),
        ToolDefinition(
            name: "calendar_update_event",
            description: "Change an event by id and occurrence start. Span is this_event (default) or future_events for repeating events."
        ),
        ToolDefinition(
            name: "calendar_delete_event",
            description: "Delete an event by id and occurrence start. Span is this_event (default) or future_events for repeating events."
        ),
    ]

    public let store: CalendarStore
    @ObservationIgnored let now: @Sendable () -> Date
    var mode: CalendarViewMode = .day
    var focusDate: Date

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
