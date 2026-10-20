import EventKit
import Observation

public enum CalendarAccess: Sendable {
    case notDetermined, granted, denied
}

/// The only type that touches `EKEventStore`. Other modules read events through
/// `events(from:to:)` and `nextEvent(after:)` and observe `changeToken`.
@MainActor
@Observable
public final class CalendarStore {
    public private(set) var access: CalendarAccess
    /// Bumps on `.EKEventStoreChanged`, so views and other modules re-read events.
    public private(set) var changeToken = 0

    @ObservationIgnored let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        access = Self.currentAccess()
        // ponytail: observer is never removed; the store lives as long as the app.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changeToken += 1 }
        }
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refreshAccess()
    }

    /// Re-reads the authorization status, for example after the owner changes it in System Settings.
    public func refreshAccess() {
        let current = Self.currentAccess()
        if current != access {
            access = current
            changeToken += 1
        }
    }

    public func events(from start: Date, to end: Date) -> [CalendarEventItem] {
        ekEvents(from: start, to: end).map(CalendarEventItem.init)
    }

    public func nextEvent(after date: Date) -> CalendarEventItem? {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: date)!
        return BTKit.nextEvent(in: events(from: date, to: end), after: date)
    }

    public func writableCalendars() -> [EKCalendar] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public var defaultCalendar: EKCalendar? {
        access == .granted ? store.defaultCalendarForNewEvents : nil
    }

    /// The occurrence `item` refers to. Searches a window around the occurrence start
    /// because a moved occurrence keeps its original `occurrenceDate` but not its start.
    public func event(for item: CalendarEventItem) -> EKEvent? {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: item.occurrenceStart)!
        let end = calendar.date(byAdding: .day, value: 8, to: item.occurrenceStart)!
        let match = ekEvents(from: start, to: end).first {
            $0.calendarItemIdentifier == item.eventIdentifier && ($0.occurrenceDate ?? $0.startDate) == item.occurrenceStart
        }
        // No series-master fallback: for a repeating event it is the first occurrence, not the one clicked.
        if match == nil && !item.isRecurring {
            return store.calendarItem(withIdentifier: item.eventIdentifier) as? EKEvent
        }
        return match
    }

    public func newEvent() -> EKEvent {
        EKEvent(eventStore: store)
    }

    public func save(_ event: EKEvent, span: EditSpan) throws {
        try store.save(event, span: span.ekSpan, commit: true)
    }

    public func delete(_ event: EKEvent, span: EditSpan) throws {
        try store.remove(event, span: span.ekSpan, commit: true)
    }

    func ekEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}

extension CalendarEventItem {
    init(_ event: EKEvent) {
        self.init(
            eventIdentifier: event.calendarItemIdentifier,
            occurrenceStart: event.occurrenceDate ?? event.startDate,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar?.title ?? "",
            colorHex: event.calendar?.cgColor.flatMap(hexString),
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            isRecurring: event.hasRecurrenceRules || event.isDetached,
            isEditable: event.calendar?.allowsContentModifications ?? false
        )
    }
}

private func hexString(_ color: CGColor) -> String? {
    guard
        let srgb = CGColorSpace(name: CGColorSpace.sRGB),
        let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
        let parts = converted.components, parts.count >= 3
    else { return nil }
    return String(format: "#%02X%02X%02X", Int(parts[0] * 255), Int(parts[1] * 255), Int(parts[2] * 255))
}
