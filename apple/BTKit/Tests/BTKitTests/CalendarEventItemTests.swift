import EventKit
import Foundation
import Testing
@testable import BTKit

private func item(
    _ id: String,
    title: String? = nil,
    start: Date,
    end: Date? = nil,
    allDay: Bool = false
) -> CalendarEventItem {
    CalendarEventItem(
        eventIdentifier: id,
        occurrenceStart: start,
        title: title ?? id,
        start: start,
        end: end ?? start.addingTimeInterval(3600),
        isAllDay: allDay,
        calendarTitle: "Home",
        colorHex: nil,
        location: nil,
        isRecurring: false,
        isEditable: true
    )
}

struct CalendarEventItemTests {
    let calendar = testCalendar()

    @Test func nextEventSkipsAllDay() {
        let items = [
            item("allday", start: date(2026, 10, 21), end: date(2026, 10, 22), allDay: true),
            item("timed", start: date(2026, 10, 21, 15)),
        ]
        #expect(nextEvent(in: items, after: date(2026, 10, 20, 23))?.eventIdentifier == "timed")
    }

    @Test func nextEventSkipsInProgress() {
        let items = [
            item("now", start: date(2026, 10, 21, 13)),
            item("later", start: date(2026, 10, 21, 15)),
        ]
        #expect(nextEvent(in: items, after: date(2026, 10, 21, 13, 30))?.eventIdentifier == "later")
    }

    @Test func nextEventIsEarliestUpcoming() {
        let items = [
            item("c", start: date(2026, 10, 21, 18)),
            item("a", start: date(2026, 10, 21, 14)),
            item("b", start: date(2026, 10, 21, 16)),
        ]
        #expect(nextEvent(in: items, after: date(2026, 10, 21, 9))?.eventIdentifier == "a")
        #expect(nextEvent(in: items, after: date(2026, 10, 21, 19)) == nil)
    }

    @Test func multiDayEventAppearsOnEachDay() {
        // Mon 2026-10-19 through Wed 2026-10-21, as EventKit reports all-day ends.
        let trip = item("trip", start: date(2026, 10, 19), end: date(2026, 10, 21, 23, 59), allDay: true)
        for day in 19...21 {
            let result = items([trip], on: date(2026, 10, day), calendar: calendar)
            #expect(result.allDay.map(\.eventIdentifier) == ["trip"])
            #expect(result.timed.isEmpty)
        }
        #expect(items([trip], on: date(2026, 10, 18), calendar: calendar).allDay.isEmpty)
        #expect(items([trip], on: date(2026, 10, 22), calendar: calendar).allDay.isEmpty)
    }

    @Test func snapshotNextAndCount() {
        let items = [
            item("cs", title: "CS 3013", start: date(2026, 10, 21, 14)),
            item("b", start: date(2026, 10, 21, 16)),
            item("c", start: date(2026, 10, 21, 18)),
        ]
        let snapshot = calendarSnapshot(items: items, now: date(2026, 10, 21, 13, 20), calendar: calendar)
        #expect(snapshot == "Calendar: next is CS 3013 at 2:00 PM (in 40m), id cs; 2 more events today.")
    }

    @Test func snapshotSingularAndNoneMore() {
        let one = [
            item("a", title: "Lab", start: date(2026, 10, 21, 14)),
            item("b", start: date(2026, 10, 21, 16, 30)),
        ]
        #expect(calendarSnapshot(items: one, now: date(2026, 10, 21, 12, 45), calendar: calendar)
            == "Calendar: next is Lab at 2:00 PM (in 1h 15m), id a; 1 more event today.")
        #expect(calendarSnapshot(items: one, now: date(2026, 10, 21, 15), calendar: calendar)
            == "Calendar: next is b at 4:30 PM (in 1h 30m), id b.")
    }

    @Test func snapshotNothingLeft() {
        let items = [
            item("a", start: date(2026, 10, 21, 9)),
            item("tomorrow", start: date(2026, 10, 22, 9)),
        ]
        #expect(calendarSnapshot(items: items, now: date(2026, 10, 21, 13), calendar: calendar)
            == "Calendar: nothing else today.")
    }

    @Test func spanMapping() {
        #expect(EditSpan.thisEvent.ekSpan == .thisEvent)
        #expect(EditSpan.futureEvents.ekSpan == .futureEvents)
        #expect(EditSpan.thisEvent.rawValue == "this_event")
        #expect(EditSpan.futureEvents.rawValue == "future_events")
    }

    @Test func recurrenceRoundTrip() {
        let options: [RecurrenceOption] = [.daily, .weekly, .biweekly, .monthly, .yearly]
        for option in options {
            #expect(recurrenceOption(from: recurrenceRules(for: option, end: nil)) == option)
        }
        let biweekly = recurrenceRules(for: .biweekly, end: nil)?.first
        #expect(biweekly?.frequency == .weekly)
        #expect(biweekly?.interval == 2)
        #expect(recurrenceOption(from: nil) == RecurrenceOption.none)
        #expect(recurrenceRules(for: .none, end: nil) == [])
    }

    @Test func recurrenceEndIsApplied() {
        let end = date(2026, 12, 1)
        let rule = recurrenceRules(for: .weekly, end: end)?.first
        #expect(rule?.recurrenceEnd?.endDate == end)
    }

    @Test func customRuleIsPreservedWhenUnchanged() {
        let monWed = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.wednesday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        let option = recurrenceOption(from: [monWed])
        guard case .custom = option else {
            Issue.record("expected custom, got \(option)")
            return
        }
        #expect(recurrenceRules(for: option, end: nil) == nil)
    }
}
