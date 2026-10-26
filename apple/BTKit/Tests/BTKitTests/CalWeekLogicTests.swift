import Foundation
import Testing
@testable import BTKit

struct CalWeekLogicTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String = "Event", start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(id: title, title: title, start: start, end: end, kind: .work, source: .apple)
    }

    @Test func weekAlwaysStartsSundayWithoutChangingSharedCalendar() {
        let days = CalWeekLayout.days(containing: date(28), calendar: calendar)
        #expect(days == (25...31).map { date($0) })
        #expect(calendar.firstWeekday == 2)
        #expect(CalWeekLayout.weekTitle(date(28), calendar: calendar) == "October 25 – 31")
    }

    @Test func timelineShowsEarlyEventsAndKeepsTheirTimes() {
        let work = event(start: date(28, 6), end: date(28, 12))
        let frame = CalWeekLayout.frame(work, on: date(28), calendar: calendar)!
        #expect(frame.y == 601)
        #expect(frame.height == 598)
        #expect(CalWeekLayout.range(work, calendar: calendar) == "6 AM – 12 PM")
        #expect(CalWeekLayout.gridHeight == 2400)
        #expect(CalWeekLayout.initialScroll == 900)
    }

    @Test func timelineShowsBothSidesOfMidnightAndClipsAtDayBoundaries() {
        #expect(CalWeekLayout.frame(event(start: date(28, 5), end: date(28, 7)), on: date(28), calendar: calendar)?.y == 501)
        let late = event(start: date(28, 23), end: date(29, 1))
        #expect(CalWeekLayout.frame(late, on: date(28), calendar: calendar)?.y == 2301)
        #expect(CalWeekLayout.frame(late, on: date(28), calendar: calendar)?.height == 98)
        #expect(CalWeekLayout.frame(late, on: date(29), calendar: calendar)?.height == 98)
        let overnight = event(start: date(27, 22), end: date(28, 9))
        #expect(CalWeekLayout.frame(overnight, on: date(28), calendar: calendar)?.height == 898)
        #expect(CalWeekLayout.frame(late, on: date(30), calendar: calendar) == nil)
    }

    @Test func rangesDropRedundantSuffixAndWholeHourMinutes() {
        #expect(CalWeekLayout.range(event(start: date(28, 9, 30), end: date(28, 10, 45)), calendar: calendar) == "9:30 – 10:45 AM")
        #expect(CalWeekLayout.range(event(start: date(28, 10), end: date(28, 11, 30)), calendar: calendar) == "10 – 11:30 AM")
        #expect(CalWeekLayout.range(event(start: date(28, 11), end: date(28, 12, 30)), calendar: calendar) == "11 AM – 12:30 PM")
    }

    @Test func weeklyViewShowsPointEventsAndDeadlinesWithoutInventingDuration() {
        let assignment = event("Assignment", start: date(28, 23, 59), end: date(28, 23, 59))
        var deadline = event("Deadline", start: date(28), end: date(28))
        deadline.kind = .deadline
        let items = [assignment, deadline]
        #expect(CalWeekLayout.events(on: date(28), in: items, calendar: calendar).count == 2)
        #expect(CalWeekLayout.events(on: date(27), in: items, calendar: calendar).isEmpty)
        #expect(CalWeekLayout.events(on: date(29), in: items, calendar: calendar).isEmpty)
        #expect(CalWeekLayout.frame(deadline, on: date(28), calendar: calendar)?.height == 20)
        let frame = CalWeekLayout.frame(assignment, on: date(28), calendar: calendar)
        #expect(frame != nil)
        if let frame {
            #expect(frame.height == 20)
            #expect(frame.y + frame.height <= CalWeekLayout.gridHeight)
        }
        #expect(CalWeekLayout.frame(assignment, on: date(29), calendar: calendar) == nil)
        #expect(CalWeekLayout.range(assignment, calendar: calendar) == "11:59 PM")
        let meeting = event("Meeting", start: date(28, 23), end: date(29))
        #expect(CalWeekLayout.conflicts(for: meeting, in: items).isEmpty)
        #expect(CalWeekLayout.conflicts(for: assignment, in: [meeting]).isEmpty)
    }

    @Test func nextEventsAreRealTimedEventsWithinShownWeek() {
        let now = date(25, 13, 22)
        var allDay = event("All day", start: date(26), end: date(27))
        allDay.isAllDay = true
        var deadline = event("Deadline", start: date(25, 16), end: date(25, 17))
        deadline.kind = .deadline
        let gym = event("Gym", start: date(25, 14, 30), end: date(25, 16, 30))
        let ongoing = event("Ongoing", start: date(25, 13), end: date(25, 14))
        let nextWeek = event("Next week", start: date(32, 10), end: date(32, 11))
        let upcoming = CalWeekLayout.upcoming([nextWeek, allDay, deadline, gym, ongoing], week: date(25), now: now, calendar: calendar)
        #expect(upcoming.map(\.id) == [gym.id, deadline.id])
        #expect(CalWeekLayout.countdown(to: gym.start, now: now, calendar: calendar) == "IN 1H 8M")
        #expect(CalWeekLayout.countdown(to: now + 120, now: now, calendar: calendar) == "IN 2M")
        #expect(CalWeekLayout.countdown(to: date(27, 10), now: now, calendar: calendar) == "TUESDAY")
    }

    @Test func conflictsUseActualIntervalsNotSharedLayoutGroups() {
        let first = event("First", start: date(26, 10), end: date(26, 12))
        let overlap = event("Overlap", start: date(26, 11), end: date(26, 13))
        let touching = event("Touching", start: date(26, 12), end: date(26, 13))
        #expect(CalWeekLayout.conflicts(for: first, in: [first, touching, overlap]).map(\.id) == [overlap.id])
    }

    @Test func kindsComeFromCalendarMetadataAndNativeBTKind() {
        var item = event(start: date(26, 10), end: date(26, 11))
        item.calendarTitle = "UARK"
        #expect(CalWeekKind.classify(item) == .classSession)
        item.title = "Chem Office Hours"
        #expect(CalWeekKind.classify(item) == .meeting)
        item.title = "Check-in"
        item.calendarTitle = "Home"
        item.hasAttendees = true
        #expect(CalWeekKind.classify(item) == .meeting)
        item.hasAttendees = false
        #expect(CalWeekKind.classify(item) == .personal)
        item.calendarTitle = "Work"
        #expect(CalWeekKind.classify(item) == .work)
        item.calendarTitle = "Focus"
        #expect(CalWeekKind.classify(item) == .studyBlock)
        item.calendarTitle = nil
        item.kind = .studyPlanned
        #expect(CalWeekKind.classify(item) == .studyBlock)
    }

    @Test func upcomingIsCappedAtEightAndIncludesSaturday() {
        let events = (0..<10).map { index in
            event("Item \(index)", start: date(31, 8 + index), end: date(31, 9 + index))
        }
        let upcoming = CalWeekLayout.upcoming(events.reversed(), week: date(28), now: date(25), calendar: calendar)
        #expect(upcoming.map(\.id) == Array(events.prefix(8)).map(\.id))
        #expect(CalWeekLayout.upcoming(events, week: date(18), now: date(25), calendar: calendar).isEmpty)
    }

    @Test func conflictHandoffIncludesRealDatesTimesAndLocations() {
        var selected = event("Lab", start: date(27, 11), end: date(27, 12, 30))
        selected.location = "Science Building"
        let conflict = event("Office Hours", start: date(27, 10), end: date(27, 12))
        let prompt = CalWeekLayout.conflictPrompt(for: selected, conflicts: [conflict], calendar: calendar)
        #expect(prompt.contains("Lab — Tuesday, October 27, 2026, 11 AM – 12:30 PM, Science Building"))
        #expect(prompt.contains("Office Hours"))
        #expect(prompt.contains("without changing anything until I approve"))
    }
}
