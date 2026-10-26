import Foundation
import Testing
@testable import BTKit

struct CalWeekLayoutTests {
    private func event(_ title: String, day: Int = 25, start: Int, end: Int) -> CalendarEvent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
        return CalendarEvent(
            id: title, title: title,
            start: midnight.addingTimeInterval(Double(start) * 60),
            end: midnight.addingTimeInterval(Double(end) * 60),
            kind: .work, source: .apple
        )
    }

    @Test func tuesdayLaterClassCascadesAboveOfficeHours() {
        let office = event("Chem Office Hours", day: 27, start: 660, end: 750)
        let lecture = event("GNEG 11101", day: 27, start: 710, end: 760)
        let placed = CalWeekLayout.cascade([lecture, office])

        #expect(placed.map(\.event.id) == [office.id, lecture.id])
        #expect(placed.map(\.indent) == [0, 1])
        #expect(placed.map(\.cols) == [1, 1])
        #expect(placed.map(\.col) == [0, 0])
        #expect(placed[1].z > placed[0].z)
        #expect(placed[0].groupID != placed[1].groupID)
    }

    @Test func mondayNearbyStartsShareWidth() {
        let office = event("Chem Office Hours", day: 26, start: 750, end: 825)
        let lecture = event("MATH 26103", day: 26, start: 775, end: 825)
        let placed = CalWeekLayout.cascade([lecture, office])

        #expect(placed.map(\.indent) == [0, 0])
        #expect(placed.map(\.cols) == [2, 2])
        #expect(placed.map(\.col) == [0, 1])
        #expect(placed[0].groupID == placed[1].groupID)
    }

    @Test func thursdayOfficeHoursCascadeAboveEarlierHistoryClass() {
        let office = event("Chem Office Hours", day: 29, start: 600, end: 720)
        let lecture = event("HIST 20103", day: 29, start: 570, end: 645)
        let placed = CalWeekLayout.cascade([office, lecture])

        #expect(placed.map(\.event.id) == [lecture.id, office.id])
        #expect(placed.map(\.indent) == [0, 1])
        #expect(placed.map(\.cols) == [1, 1])
        #expect(placed[1].z > placed[0].z)
    }

    @Test func wednesdayEarlyWorkKeepsRealTimesForClippingAndLabels() {
        let work = event("Work", day: 28, start: 360, end: 720)
        let office = event("Chem Office Hours", day: 28, start: 600, end: 690)
        let placed = CalWeekLayout.cascade([office, work])

        #expect(placed.map(\.indent) == [0, 1])
        #expect(placed.map(\.cols) == [1, 1])
        #expect(placed[0].event == work)
        #expect(placed[1].event == office)
        #expect(placed[1].z > placed[0].z)
    }

    @Test func sundaySingleEventUsesFullWidth() {
        let gym = event("Gym with Hardik", start: 870, end: 990)
        let placed = CalWeekLayout.cascade([gym])

        #expect(placed.count == 1)
        #expect(placed[0].event == gym)
        #expect(placed[0].indent == 0)
        #expect(placed[0].col == 0)
        #expect(placed[0].cols == 1)
        #expect(placed[0].z == 10)
    }

    @Test func emptyDayHasNoPlacements() {
        #expect(CalWeekLayout.cascade([]).isEmpty)
    }

    @Test func simultaneousStartsPlaceLongestEventFirst() {
        let short = event("Short", start: 600, end: 630)
        let long = event("Long", start: 600, end: 720)
        let placed = CalWeekLayout.cascade([short, long])

        #expect(placed.map(\.event.id) == [long.id, short.id])
        #expect(placed.map(\.indent) == [0, 0])
        #expect(placed.map(\.cols) == [2, 2])
        #expect(placed.map(\.col) == [0, 1])
    }

    @Test func touchingEventsStartIndependentGroups() {
        let first = event("First", start: 600, end: 630)
        let second = event("Second", start: 630, end: 660)
        let placed = CalWeekLayout.cascade([second, first])

        #expect(placed.map(\.indent) == [0, 0])
        #expect(placed.map(\.cols) == [1, 1])
        #expect(placed[0].groupID != placed[1].groupID)
    }

    @Test func nearbyStartsShareTheExistingCascadedGroup() {
        let work = event("Work", start: 420, end: 780)
        let office = event("Office", start: 600, end: 720)
        let meeting = event("Meeting", start: 620, end: 660)
        let placed = CalWeekLayout.cascade([meeting, office, work])

        #expect(placed.map(\.indent) == [0, 1, 1])
        #expect(placed.map(\.cols) == [1, 2, 2])
        #expect(placed.map(\.col) == [0, 0, 1])
        #expect(placed[1].groupID == placed[2].groupID)
    }

    @Test func laterOverlapsIncreaseDepthAndResetAfterTheGroupEnds() {
        let work = event("Work", start: 420, end: 780)
        let office = event("Office", start: 600, end: 720)
        let meeting = event("Meeting", start: 660, end: 750)
        let dinner = event("Dinner", start: 1080, end: 1140)
        let placed = CalWeekLayout.cascade([dinner, meeting, office, work])

        #expect(placed.map(\.indent) == [0, 1, 2, 0])
        #expect(placed.map(\.cols) == [1, 1, 1, 1])
        #expect(placed.map(\.z) == [10, 11, 12, 13])
    }
}
