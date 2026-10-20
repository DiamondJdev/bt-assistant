import Foundation
import Testing
@testable import BTKit

func testCalendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.locale = Locale(identifier: "en_US")
    calendar.firstWeekday = firstWeekday
    return calendar
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = testCalendar()) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct CalendarRangeTests {
    @Test func weekStartsOnFirstWeekday() {
        let sunday = testCalendar(firstWeekday: 1)
        let interval = visibleInterval(for: .week, containing: date(2026, 10, 21), calendar: sunday)
        #expect(interval.start == date(2026, 10, 18))
        #expect(interval.end == date(2026, 10, 25))

        let monday = testCalendar(firstWeekday: 2)
        let mondayInterval = visibleInterval(for: .week, containing: date(2026, 10, 21), calendar: monday)
        #expect(mondayInterval.start == date(2026, 10, 19))
        #expect(weekDays(containing: date(2026, 10, 21), calendar: monday).first == date(2026, 10, 19))
        #expect(weekDays(containing: date(2026, 10, 21), calendar: monday).count == 7)
    }

    @Test func monthGridCoversWholeWeeks() {
        let calendar = testCalendar()
        let days = monthGridDays(containing: date(2026, 10, 15), calendar: calendar)
        #expect(days.first == date(2026, 9, 27))
        #expect(days.count % 7 == 0)
        #expect(days.count == 35 || days.count == 42)
        #expect(days.contains(date(2026, 10, 31)))
    }

    @Test func steppingMonthFromJan31LandsInFebruary() {
        let calendar = testCalendar()
        let next = stepped(date(2026, 1, 31), by: .month, forward: true, calendar: calendar)
        #expect(calendar.component(.month, from: next) == 2)
        #expect(calendar.component(.year, from: next) == 2026)
    }

    @Test func dayRangeAcrossDSTIsOneCalendarDay() {
        let calendar = testCalendar()
        let interval = visibleInterval(for: .day, containing: date(2026, 11, 1, 12), calendar: calendar)
        #expect(interval.duration == 25 * 3600)
        #expect(interval.start == date(2026, 11, 1))
        #expect(interval.end == date(2026, 11, 2))
    }

    @Test func timelinePositionUsesLocalClockOnDSTDay() {
        let calendar = testCalendar()
        let day = date(2026, 11, 1)
        #expect(minutesIntoDay(date(2026, 11, 1, 15), day: day, calendar: calendar) == 15 * 60)
        #expect(minutesIntoDay(date(2026, 10, 31, 22), day: day, calendar: calendar) == 0)
        #expect(minutesIntoDay(date(2026, 11, 2, 1), day: day, calendar: calendar) == 24 * 60)
    }

    @Test func newEventStartsOnQuarterHours() {
        let calendar = testCalendar()
        let now = date(2026, 10, 21, 13, 7)
        #expect(defaultNewEventStart(on: now, now: now, calendar: calendar) == date(2026, 10, 21, 13, 15))
        #expect(defaultNewEventStart(on: date(2026, 10, 21, 13, 15), now: date(2026, 10, 21, 13, 15), calendar: calendar)
            == date(2026, 10, 21, 13, 30))
        #expect(defaultNewEventStart(on: date(2026, 10, 23), now: now, calendar: calendar) == date(2026, 10, 23, 9))
        // A click 14h 40m down the timeline rounds down to 14:30.
        #expect(slotStart(minutes: 14 * 60 + 40, day: date(2026, 10, 21), calendar: calendar) == date(2026, 10, 21, 14, 30))
    }

    @Test func overlappingEventsShareColumns() {
        func event(_ id: String, _ startHour: Int, _ endHour: Int) -> CalendarEventItem {
            CalendarEventItem(
                eventIdentifier: id, occurrenceStart: date(2026, 10, 21, startHour), title: id,
                start: date(2026, 10, 21, startHour), end: date(2026, 10, 21, endHour), isAllDay: false,
                calendarTitle: "", colorHex: nil, location: nil, isRecurring: false, isEditable: true
            )
        }
        let a = event("a", 9, 11), b = event("b", 10, 12), c = event("c", 11, 13), d = event("d", 14, 15)
        let layout = timelineLayout([a, b, c, d])
        #expect(layout[a.id]?.column == 0 && layout[a.id]?.columns == 2)
        #expect(layout[b.id]?.column == 1 && layout[b.id]?.columns == 2)
        #expect(layout[c.id]?.column == 0 && layout[c.id]?.columns == 2)
        #expect(layout[d.id]?.column == 0 && layout[d.id]?.columns == 1)
    }
}
