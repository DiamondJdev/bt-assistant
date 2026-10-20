import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct FocusLogTests {
    let container: ModelContainer
    let log: FocusLog
    var calendar = Calendar(identifier: .gregorian)
    let today: Date

    init() throws {
        container = try ModelContainer(
            for: FocusSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        log = FocusLog(context: container.mainContext)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    }

    func at(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func record(_ start: Date, minutes: Double) throws {
        try log.record(FocusInterval(start: start, end: start + minutes * 60), label: nil)
    }

    @Test func recordStoresIntervalWithFocusedSeconds() throws {
        try record(at(dayOffset: 0, hour: 10), minutes: 25)

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.focusedSeconds == 1500)
        #expect(sessions.first?.start == at(dayOffset: 0, hour: 10))
        #expect(sessions.first?.end == at(dayOffset: 0, hour: 10, minute: 25))
        #expect(sessions.first?.eventIdentifier == nil)
    }

    @Test func totalTodaySumsOnlyThatDay() throws {
        try record(at(dayOffset: 0, hour: 9), minutes: 25)
        try record(at(dayOffset: 0, hour: 14), minutes: 15)
        try record(at(dayOffset: -1, hour: 9), minutes: 25)

        #expect(log.totalFocused(on: today, calendar: calendar) == 2400)
    }

    @Test func totalTodayUsesEndDate() throws {
        try record(at(dayOffset: -1, hour: 23, minute: 50), minutes: 25)

        #expect(log.totalFocused(on: today, calendar: calendar) == 1500)
        #expect(log.totalFocused(on: at(dayOffset: -1, hour: 12), calendar: calendar) == 0)
    }

    @Test func lastSevenDaysIncludesTodayAndSixPrior() throws {
        try record(at(dayOffset: 0, hour: 9), minutes: 25)
        try record(at(dayOffset: -6, hour: 9), minutes: 10)
        try record(at(dayOffset: -7, hour: 9), minutes: 40)

        #expect(log.totalFocused(lastDays: 7, endingOn: today, calendar: calendar) == 2100)
    }
}
