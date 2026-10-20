#if DEBUG
import EventKit
import os

/// Temporary early check for recurring edits (calendar plan, task 3). Removed in task 6.
/// Only touches events it creates, titled "BT recurring test".
extension CalendarStore {
    func runRecurringEditCheck() {
        let log = Logger(subsystem: "com.diamondjdev.bt", category: "RecurringCheck")
        let prefix = "BT recurring test"
        guard let calendar = defaultCalendar else {
            log.error("RecurringCheck: no default calendar or no access")
            return
        }
        let cal = Calendar.current
        let nextMonday = cal.nextDate(after: .now, matching: DateComponents(hour: 10, weekday: 2), matchingPolicy: .nextTime)!
        let windowEnd = cal.date(byAdding: .day, value: 30, to: nextMonday)!

        func ours() -> [EKEvent] {
            let predicate = store.predicateForEvents(withStart: nextMonday.addingTimeInterval(-3600), end: windowEnd, calendars: [calendar])
            return store.events(matching: predicate)
                .filter { ($0.title ?? "").hasPrefix(prefix) }
                .sorted { ($0.occurrenceDate ?? $0.startDate) < ($1.occurrenceDate ?? $1.startDate) }
        }
        func dump(_ label: String) -> [EKEvent] {
            let events = ours()
            for (index, event) in events.enumerated() {
                log.notice("RecurringCheck \(label, privacy: .public) #\(index + 1): occurrence \(String(describing: event.occurrenceDate), privacy: .public) start \(event.startDate, privacy: .public) title \(event.title ?? "", privacy: .public) id \(event.calendarItemIdentifier, privacy: .public)")
            }
            return events
        }

        do {
            guard ours().isEmpty else {
                log.error("RecurringCheck: leftover test events in window, aborting")
                return
            }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = prefix
            event.startDate = nextMonday
            event.endDate = nextMonday.addingTimeInterval(3600)
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4))]
            try save(event, span: .thisEvent)
            let created = dump("created")

            let second = created[1]
            second.startDate = second.startDate.addingTimeInterval(3600)
            second.endDate = second.endDate.addingTimeInterval(3600)
            try save(second, span: .thisEvent)

            let third = ours()[2]
            third.title = "\(prefix) renamed"
            try save(third, span: .futureEvents)

            let result = dump("after edits")
            let starts: [Date] = created.map { $0.startDate }
            let pass = result.count == 4
                && result[0].startDate == starts[0] && result[0].title == prefix
                && result[1].startDate == starts[1].addingTimeInterval(3600) && result[1].title == prefix
                && result[2].startDate == starts[2] && result[2].title == "\(prefix) renamed"
                && result[3].startDate == starts[3] && result[3].title == "\(prefix) renamed"
            log.notice("RecurringCheck result: \(pass ? "PASS" : "FAIL", privacy: .public)")

            // Delete each series from its first occurrence.
            var seen = Set<String>()
            for event in result where seen.insert(event.calendarItemIdentifier).inserted {
                try delete(event, span: .futureEvents)
            }
            let left = ours().count
            log.notice("RecurringCheck cleanup: \(left) test events left")
        } catch {
            log.error("RecurringCheck error: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
