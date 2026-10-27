import Foundation
import Testing
@testable import BTKit

struct CodingSessionsTests {
    var calendar = Calendar(identifier: .gregorian)
    let today: Date

    init() {
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    }

    func at(dayOffset: Int = 0, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    func beat(_ time: Date, _ project: String = "bt", _ language: String = "swift") -> Heartbeat {
        Heartbeat(timestamp: time, editor: "vscode", project: project, language: language)
    }

    func session(_ start: Date, _ end: Date, _ project: String = "bt", _ language: String = "swift") -> CodingSession {
        CodingSession(start: start, end: end, project: project, language: language)
    }

    @Test func gapOfExactlyFifteenMinutesStaysInOneSession() {
        let sessions = sessionize([beat(at(hour: 9)), beat(at(hour: 9, minute: 15))])
        #expect(sessions == [session(at(hour: 9), at(hour: 9, minute: 16))])
    }

    @Test func gapJustOverFifteenMinutesSplits() {
        let sessions = sessionize([beat(at(hour: 9)), beat(at(hour: 9, minute: 15, second: 1))])
        #expect(sessions == [
            session(at(hour: 9), at(hour: 9, minute: 1)),
            session(at(hour: 9, minute: 15, second: 1), at(hour: 9, minute: 16, second: 1)),
        ])
    }

    @Test func projectChangeSplits() {
        let sessions = sessionize([
            beat(at(hour: 9), "bt"),
            beat(at(hour: 9, minute: 5), "bt"),
            beat(at(hour: 9, minute: 10), "other"),
        ])
        #expect(sessions == [
            session(at(hour: 9), at(hour: 9, minute: 6), "bt"),
            session(at(hour: 9, minute: 10), at(hour: 9, minute: 11), "other"),
        ])
    }

    @Test func sessionEndsNoLaterThanTheNextOneStarts() {
        let sessions = sessionize([beat(at(hour: 9), "bt"), beat(at(hour: 9, second: 20), "other")])
        #expect(sessions.first?.end == at(hour: 9, second: 20))
        #expect(sessions.map(\.duration) == [20, 60])
    }

    @Test func loneBeatIsOneMinute() {
        let sessions = sessionize([beat(at(hour: 9))])
        #expect(sessions.map(\.duration) == [60])
        #expect(sessionize([]).isEmpty)
    }

    @Test func unsortedInputIsSorted() {
        let sessions = sessionize([beat(at(hour: 9, minute: 10)), beat(at(hour: 9)), beat(at(hour: 9, minute: 5))])
        #expect(sessions == [session(at(hour: 9), at(hour: 9, minute: 11))])
    }

    @Test func languageIsTheMajorityWithTiesToTheLatest() {
        let majority = sessionize([
            beat(at(hour: 9), "bt", "swift"),
            beat(at(hour: 9, minute: 1), "bt", "python"),
            beat(at(hour: 9, minute: 2), "bt", "swift"),
        ])
        let tie = sessionize([
            beat(at(hour: 9), "bt", "swift"),
            beat(at(hour: 9, minute: 1), "bt", "python"),
        ])
        #expect(majority.first?.language == "swift")
        #expect(tie.first?.language == "python")
    }

    @Test func sessionCrossingMidnightCountsTowardTheDayItStarted() {
        let sessions = sessionize([
            beat(at(dayOffset: -1, hour: 23, minute: 50)),
            beat(at(hour: 0, minute: 5)),
        ])
        let stats = codingStats(sessions, days: 2, endingOn: today, calendar: calendar)

        #expect(sessions.count == 1)
        #expect(stats.perDay == [
            CodingDayTotal(day: at(dayOffset: -1, hour: 0), seconds: 16 * 60),
            CodingDayTotal(day: at(hour: 0), seconds: 0),
        ])
    }

    @Test func statsGroupAcrossAWeek() {
        let sessions = [
            session(at(hour: 9), at(hour: 10), "bt", "swift"),
            session(at(hour: 11), at(hour: 11, minute: 30), "web", "typescript"),
            session(at(dayOffset: -3, hour: 9), at(dayOffset: -3, hour: 9, minute: 45), "web", "swift"),
            session(at(dayOffset: -6, hour: 9), at(dayOffset: -6, hour: 9, minute: 10), "bt", "python"),
            session(at(dayOffset: -7, hour: 9), at(dayOffset: -7, hour: 12), "old", "c"),
        ]

        let stats = codingStats(sessions, days: 7, endingOn: today, calendar: calendar)

        #expect(stats.total == (60 + 30 + 45 + 10) * 60)
        #expect(stats.perDay.count == 7)
        #expect(stats.perDay.first == CodingDayTotal(day: at(dayOffset: -6, hour: 0), seconds: 600))
        #expect(stats.perDay[3] == CodingDayTotal(day: at(dayOffset: -3, hour: 0), seconds: 45 * 60))
        #expect(stats.perDay.last == CodingDayTotal(day: at(hour: 0), seconds: 90 * 60))
        #expect(stats.byProject == [CodingTotal(name: "web", seconds: 75 * 60), CodingTotal(name: "bt", seconds: 70 * 60)])
        #expect(stats.byLanguage == [
            CodingTotal(name: "swift", seconds: 105 * 60),
            CodingTotal(name: "typescript", seconds: 30 * 60),
            CodingTotal(name: "python", seconds: 10 * 60),
        ])
    }
}
