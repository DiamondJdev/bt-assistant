import Foundation
import Testing
@testable import BTKit

@MainActor
struct CodeScreenMetricsTests {
    let store = AppStore(clock: { AppStoreTests.thursday })

    func week(_ id: String) -> CodeWeek {
        CodeWeek(activity: store.project(id)!.activity, now: store.now, calendar: store.calendar)
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func weeklyTotalsAndShare() {
        #expect(week("bt-client").weekMinutes == 340)
        #expect(week("tariffninja").weekMinutes == 112)
        #expect(week("mirai").weekMinutes == 59)
        #expect(week("waypave").weekMinutes == 0)
        let lastWeek = store.projects.reduce(0) { $0 + CodeWeek(activity: $1.activity, now: store.now, calendar: store.calendar).lastWeekMinutes }
        #expect(CodeWeek.delta(minutes: 511 - lastWeek) == "+1h 12m")
        #expect(CodeWeek.duration(minutes: 340) == "5h 40m")
        #expect(CodeWeek.duration(minutes: 7) == "0h 07m")
    }

    @Test func todayMatchesTodayScreenCodeTime() {
        let today = week("bt-client").todayIndex
        #expect(week("bt-client").dailyMinutes[today] == 108)
        #expect(week("tariffninja").dailyMinutes[today] == 52)
        #expect(week("mirai").dailyMinutes[today] == 32)
    }

    @Test func sparkHasSevenDaysAndClampsHeight() {
        let days = week("bt-client").dailyMinutes
        #expect(days == [160, 30, 42, 108, 0, 0, 0])
        #expect(CodeSpark.height(minutes: 160) == 16)
        #expect(CodeSpark.height(minutes: 0) == 2)
        #expect(CodeSpark.height(minutes: 600) == 20)
    }

    @Test func statusLabels() {
        #expect(week("bt-client").status == .codingNow)
        #expect(week("tariffninja").status == .dropping(percent: -41))
        #expect(week("mirai").status == .lastTouched(weekday: nil))
        #expect(week("waypave").status == .idle(days: 9))
        #expect(CodeStatus.codingNow.label == "● Coding now")
        #expect(CodeStatus.dropping(percent: -40).label == "\u{2212}40% vs avg")
        #expect(CodeStatus.idle(days: 9).label == "Idle 9 days")
        #expect(CodeStatus.dropping(percent: -40).isAccent && !CodeStatus.idle(days: 9).isAccent)
    }

    @Test func lastTouchedNamesTheWeekday() {
        let run = CodingActivity(start: date(20, 21), end: date(20, 22), projectID: "x", source: .agent)
        let w = CodeWeek(activity: [run], now: store.now, calendar: store.calendar)
        #expect(w.status == .lastTouched(weekday: "Tue"))
        #expect(w.status.label == "Last touched Tue")
        #expect(CodeWeek(activity: [], now: store.now, calendar: store.calendar).status == .noActivity)
    }

    @Test func heatGridBucketsHoursAndMarksFuture() {
        let heat = week("bt-client").heat
        #expect(heat.count == 7 && heat.allSatisfy { $0.count == 16 })
        #expect(heat[0][6] == .level(4))   // Mon 2 PM: 60 min
        #expect(heat[0][7] == .level(3))   // Mon 3 PM: 35 min
        #expect(heat[1][13] == .level(3))  // Tue 9 PM: 30 min
        #expect(heat[0][0] == .level(0))
        #expect(heat[3][4] == .level(4))   // Thu noon, current hour
        #expect(heat[3][5] == .future)     // Thu 1 PM
        #expect(heat[4].allSatisfy { $0 == .future })
        #expect([0, 1, 14, 15, 30, 44, 45].map(CodeWeek.level) == [0, 1, 1, 2, 3, 3, 4])
    }

    @Test func bestWindow() {
        #expect(week("bt-client").bestWindow == "Best: 8 – 10 PM")
        #expect(week("tariffninja").bestWindow == "Best: 9 – 11 AM")
        #expect(week("waypave").bestWindow == "No data yet")
        #expect(CodeWeek.hourRange(11, 13, spaced: true) == "11 AM – 1 PM")
        #expect(CodeWeek.hourRange(22, 24, spaced: false) == "10 PM–12 AM")
    }

    @Test func insideFocusShareAndNote() {
        let bt = week("bt-client")
        #expect(bt.insideShare == 198.0 / 340)
        #expect(bt.insideNote == "40 min unbroken inside a session. 20 outside.")
        #expect(week("waypave").insideShare == nil)
        #expect(week("waypave").insideNote == "No sessions this week.")
    }

    @Test func streakCountsBackFromToday() {
        #expect(week("bt-client").streakDays == 4)
        #expect(week("tariffninja").streakDays == 1)
        #expect(week("waypave").streakDays == 0)
    }

    @Test func termWeekLabel() {
        #expect(CodeTermWeek.label(now: store.now, calendar: store.calendar) == "Week 9 · Oct 19 – 25")
        #expect(CodeTermWeek.label(now: date(28, 9), calendar: .bt) == "Week 10 · Oct 26 – Nov 1")
    }
}
