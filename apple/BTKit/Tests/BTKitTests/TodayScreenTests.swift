import Foundation
import Testing
@testable import BTKit

@MainActor
struct TodayScreenTests {
    /// Thursday 22 Oct 2026, 12:46.
    static let thursday = Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 46))!

    func makeStore() -> AppStore { AppStore(clock: { Self.thursday }) }

    func at(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.bt.date(bySettingHour: h, minute: m, second: 0, of: Self.thursday)!
    }

    @Test func formats() {
        let c = Calendar.bt
        #expect(TodayFormat.clock(at(13, 30), c) == "1:30")
        #expect(TodayFormat.clock(at(0, 5), c) == "12:05")
        #expect(TodayFormat.duration(3 * 3600 + 12 * 60, spaced: true) == "3h 12m")
        #expect(TodayFormat.duration(108 * 60, spaced: false) == "1h48")
        #expect(TodayFormat.duration(52 * 60, spaced: false) == "52m")
        #expect(TodayFormat.greeting(at(9), c) == "Morning")
        #expect(TodayFormat.greeting(at(12, 46), c) == "Afternoon")
        #expect(TodayFormat.greeting(at(17), c) == "Evening")
        #expect(TodayFormat.dayLabel(Self.thursday, c) == "Thu 22 Oct")
        #expect(TodayFormat.termLabel(Self.thursday, c) == "Fall · Week 9")
        #expect(TodayFormat.shortTitle("MATH 26103 · Discrete Math") == "Discrete Math")
    }

    @Test func agendaStartsWithNowAndSkipsPastEvents() {
        let rows = makeStore().todayAgenda
        #expect(rows.first?.time == "NOW")
        #expect(rows.first?.title == "Focus — calendar sync module")
        #expect(rows.first?.meta == "→ 18:42")
        #expect(!rows.contains { $0.title == "HIST 20103" })
        #expect(rows.contains { $0.time == "1:30" && $0.meta == "[ROOM]" })
        #expect(rows.last?.meta == "BLACKBOARD")
        #expect(rows.last?.title == "Discrete Math HW 6 due")
    }

    @Test func codeTimeSumsTodaysActivity() {
        let summary = makeStore().todayCodeTime
        #expect(summary.totalText == "3h 12m")
        #expect(summary.breakdown == "bt-client 1h48 · tariffninja 52m · mirai 32m")
        #expect(summary.filledSegments == 19)
        #expect(summary.percentOfGoal == 80)
    }

    /// The mockup's day: no study block at 2:55 yet.
    func mockupStore() -> AppStore {
        let store = makeStore()
        store.deleteEvent("hw6")
        return store
    }

    @Test func slotIsTenMinutesAfterNextClass() {
        let slot = mockupStore().todayBookingSlot
        #expect(slot.map { TodayFormat.clock($0.start, Calendar.bt) } == "2:55")
    }

    @Test func slotSkipsBusyTimeAndThePast() throws {
        let store = makeStore()
        let slot = try #require(store.todayBookingSlot)
        #expect(slot.start >= store.now)
        let busy = store.events(on: store.now).filter { $0.kind != .deadline && $0.kind != .focusLogged }
        #expect(!busy.contains { $0.start < slot.end && slot.start < $0.end })
    }

    @Test func noSlotLateAtNight() {
        let late = Calendar.bt.date(bySettingHour: 22, minute: 30, second: 0, of: Self.thursday)!
        #expect(AppStore(clock: { late }).todayBookingSlot == nil)
    }

    @Test func proposalCountsMinutesToNextClass() {
        let text = mockupStore().todayProposal.map(\.text).joined()
        #expect(text.hasPrefix("You have 44 minutes before Discrete Math."))
        #expect(text.contains("stop at 1:20"))
        #expect(text.hasSuffix("session 3 at 2:55."))
    }

    @Test func bookAddsBlockToAgendaAndUndoRemovesIt() throws {
        let store = mockupStore()
        let count = store.events.count
        store.bookTodaySession()
        let booked = try #require(store.todayBookedEvent)
        #expect(store.events.count == count + 1)
        #expect(booked.kind == .studyPlanned && booked.source == .bt && booked.runAsFocus)
        #expect(booked.linkedProjectID == "bt-client")
        #expect(booked.title == "Focus — session 3")
        #expect(TodayFormat.clock(booked.start, store.calendar) == "2:55")
        #expect(TodayFormat.clock(booked.end, store.calendar) == "3:45")
        #expect(store.ledger.first?.undo == .removeEvent(id: booked.id))
        let row = try #require(store.todayAgenda.first { $0.id == booked.id })
        #expect(row.meta == "BOOKED BY BT" && row.isBooked)

        store.bookTodaySession()
        #expect(store.events.count == count + 1)

        store.undoTodayBooking()
        #expect(store.todayBookedEvent == nil)
        #expect(store.events.count == count)
        #expect(store.ledger.first?.isUndone == true)
    }

    @Test func sendPostsToBTAndClearsDraft() {
        let store = makeStore()
        store.today.draft = "   "
        store.sendTodayDraft()
        #expect(store.today.sentText == nil)

        store.today.draft = " Move CHEM review "
        store.sendTodayDraft()
        #expect(store.today.sentText == "Move CHEM review")
        #expect(store.today.draft.isEmpty)
        #expect(store.thread(store.today.sentThreadID)?.messages.first?.text == "Move CHEM review")
    }
}
