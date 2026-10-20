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
}
