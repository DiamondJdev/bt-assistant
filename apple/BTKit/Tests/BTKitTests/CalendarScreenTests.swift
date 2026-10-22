import Foundation
import Testing
@testable import BTKit

@MainActor
struct CalendarScreenTests {
    static let cal = Calendar.bt
    /// Thursday 22 Oct 2026, 12:46 — the mockups' "now".
    static let thursday = at(22, 12, 46)

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func makeStore() -> AppStore { AppStore(clock: { Self.thursday }) }

    // MARK: Positioning

    @Test func blocksArePlacedOverEightToTen() {
        let f = CalTimeline.frame(start: Self.at(22, 9, 30), end: Self.at(22, 10, 45), height: 1400, cal: Self.cal)
        #expect(abs(f.y - 150) < 0.01)
        #expect(abs(f.height - 125) < 0.01)
        let top = CalTimeline.frame(start: Self.at(22, 8), end: Self.at(22, 9), height: 1400, cal: Self.cal)
        #expect(top.y == 0)
    }

    @Test func blocksOutsideTheGridClampAndKeepAMinimumHeight() {
        let early = CalTimeline.frame(start: Self.at(22, 6), end: Self.at(22, 7), height: 700, cal: Self.cal)
        #expect(early.y == 0)
        #expect(early.height == 18)
        let late = CalTimeline.frame(start: Self.at(22, 21, 50), end: Self.at(22, 23), height: 700, cal: Self.cal)
        #expect(late.y + late.height <= 700)
        #expect(!CalTimeline.isVisible(Self.at(22, 23), Self.cal))
        #expect(CalTimeline.isVisible(Self.thursday, Self.cal))
    }

    // MARK: Dates

    @Test func weekStartsMonday() {
        let days = CalDates.weekDays(Self.thursday, Self.cal)
        #expect(days.count == 7)
        #expect(days.first == Self.at(19, 0))
        #expect(days.last == Self.at(25, 0))
        #expect(CalDates.weekdayIndex(Self.thursday, Self.cal) == 3)
    }

    @Test func monthGridCoversWholeWeeks() {
        let oct = CalDates.monthGrid(Self.thursday, Self.cal)
        #expect(oct.count == 35)
        #expect(oct.first == Self.at(28, 0, month: 9))
        #expect(oct.last == Self.at(1, 0, month: 11))
        // August 2026 starts on a Saturday and needs a sixth row.
        #expect(CalDates.monthGrid(Self.at(10, 12, month: 8), Self.cal).count == 42)
    }

    @Test func stepMovesByThePeriodOfTheMode() {
        #expect(CalDates.step(Self.thursday, mode: .day, by: -1, Self.cal) == Self.at(21, 12, 46))
        #expect(CalDates.step(Self.thursday, mode: .week, by: 1, Self.cal) == Self.at(29, 12, 46))
        #expect(CalDates.step(Self.thursday, mode: .month, by: 1, Self.cal) == Self.at(22, 12, 46, month: 11))
    }

    @Test func formats() {
        #expect(CalFormat.time(Self.at(22, 17, 30), Self.cal) == "5:30")
        #expect(CalFormat.time(Self.at(22, 0, 5), Self.cal) == "12:05")
        #expect(CalFormat.hours(4.75) == "4h 45m")
        #expect(CalFormat.hours(3) == "3h")
        #expect(CalFormat.span(Self.at(26, 0), Self.at(1, 0, month: 11), Self.cal) == "Oct 26 – Nov 1")
        #expect(CalFormat.countdown(from: Self.thursday, to: Self.at(22, 23, 59)) == "11h")
        #expect(CalFormat.countdown(from: Self.thursday, to: Self.at(25, 23, 59)) == "3d")
    }

    // MARK: Layers

    @Test func hidingAWeekLayerHidesItsKinds() {
        let store = makeStore()
        let shown = CalLayers.visible(store.events, hiding: [.study, .due])
        #expect(!shown.contains { [.studyPlanned, .btDraft, .deadline].contains($0.kind) })
        #expect(shown.contains { $0.kind == .classSession })
        #expect(CalLayers.visible(store.events, hiding: []).count == store.events.count)
    }

    @Test func monthLayersLeaveWorkOffByDefault() {
        let store = makeStore()
        let shown = CalLayers.visible(store.events, showing: store.calendarScreen.monthLayers)
        #expect(!shown.contains { $0.kind == .work })
        #expect(shown.contains { $0.kind == .focusLogged })
    }

    // MARK: Popover

    @Test func popoverFlipsLeftFromFriday() {
        let cols = CalWeekColumns(width: 1000)
        #expect(!CalPopover.flipsLeft(dayIndex: 3))
        #expect(CalPopover.flipsLeft(dayIndex: 4))
        #expect(CalPopover.x(dayIndex: 3, columnX: cols.x, columnWidth: cols.columnWidth) == cols.x(3) + cols.columnWidth + 4)
        #expect(CalPopover.x(dayIndex: 5, columnX: cols.x, columnWidth: cols.columnWidth) == cols.x(5) - CalPopover.width - 4)
        #expect(CalPopover.y(blockY: 600, gridHeight: 700) == 400)
        #expect(CalPopover.y(blockY: 50, gridHeight: 700) == 50)
    }

    // MARK: New event

    @Test func newEventGoesInTheNextFreeHourAndOpens() {
        let store = makeStore()
        store.calendarMode = .month
        let e = store.calNewEvent()
        // 1–7 PM is taken by Discrete Math, HW 6, SI and the draft.
        #expect(e.start == Self.at(22, 19))
        #expect(e.kind == .studyPlanned)
        #expect(store.selectedEventID == e.id)
        #expect(store.calendarMode == .week)
    }

    @Test func nudgeKeepsLength() {
        let store = makeStore()
        let before = store.event("hw6")!
        store.calNudge("hw6", minutes: 30)
        let after = store.event("hw6")!
        #expect(after.start == before.start.addingTimeInterval(1800))
        #expect(after.duration == before.duration)
    }

    // MARK: BT draft

    @Test func keepThenUndo() {
        let store = makeStore()
        let before = store.calDraftEvent!
        store.calKeepDraft()
        #expect(store.event("draft")?.kind == .studyPlanned)
        #expect(store.calendarScreen.draft.outcome == .kept)
        #expect(CalWeekBTBar.sentence(.kept, block: store.calDraftEvent, cal: store.calendar).hasPrefix("Kept. CHEM review is on Thursday 5:30–6:30"))
        store.calUndoDraft()
        #expect(store.event("draft") == before)
        #expect(store.calendarScreen.draft.outcome == .pending)
    }

    @Test func moveLaterShiftsAnHour() {
        let store = makeStore()
        store.calMoveDraftLater()
        #expect(store.event("draft")?.start == Self.at(22, 18, 30))
        #expect(CalWeekBTBar.sentence(.moved, block: store.calDraftEvent, cal: store.calendar).hasPrefix("Moved to 6:30–7:30"))
        store.calUndoDraft()
        #expect(store.event("draft")?.start == Self.at(22, 17, 30))
    }

    @Test func discardDeletesAndUndoRestores() {
        let store = makeStore()
        store.calDiscardDraft()
        #expect(store.calDraftEvent == nil)
        #expect(store.calendarScreen.draft.outcome == .discarded)
        store.calUndoDraft()
        #expect(store.event("draft")?.kind == .btDraft)
    }

    // MARK: Day

    @Test func parseUsesDurationTitleAndAfterAnchor() {
        let store = makeStore()
        let d = CalDayDraft.parse("1h CHEM lab report after SI", day: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal)
        #expect(d.title == "CHEM lab report")
        #expect(d.start == Self.at(22, 17, 15))
        #expect(d.end == Self.at(22, 18, 15))
        #expect(d.focusText == "2 × 25 with a 5 min break")
        #expect(d.why.contains("SI"))
    }

    @Test func parseWithoutAnchorFindsOpenTime() {
        let store = makeStore()
        let d = CalDayDraft.parse("45m read chapter 3", day: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal)
        #expect(d.title == "Read chapter 3")
        #expect(d.duration == 45 * 60)
        #expect(d.start >= Self.thursday)
        #expect(!store.events.contains { $0.kind != .deadline && $0.start < d.end && $0.end > d.start })
        #expect(CalDayDraft.parse("  ", day: Self.thursday, now: Self.thursday, events: [], cal: Self.cal).title == "Study block")
    }

    @Test func addingTheDraftUpdatesHoursAndDueSoon() {
        let store = makeStore()
        let before = CalHoursBreakdown(day: Self.thursday, events: store.events(on: Self.thursday), cal: Self.cal)
        #expect(abs(before.classHours - 4.75) < 0.01)
        #expect(abs(before.focusHours - (50.0 / 60 + 1)) < 0.01)
        #expect(abs(before.openHours - (14 - before.classHours - before.focusHours)) < 0.01)
        let lab = { CalDueSoon.list(now: Self.thursday, events: store.events).first { $0.deadline.id == "due-lab" } }
        #expect(lab()?.booked.isEmpty == true)

        let d = CalDayDraft.parse(CalDayDraft.defaultPrompt, day: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal)
        store.calAddDayDraft(d)
        let after = CalHoursBreakdown(day: Self.thursday, events: store.events(on: Self.thursday), cal: Self.cal)
        #expect(abs(after.focusHours - before.focusHours - 1) < 0.01)
        #expect(lab()?.booked.count == 1)

        store.calUndoDayDraft()
        #expect(store.calendarScreen.dayDraftAddedID == nil)
        #expect(lab()?.booked.isEmpty == true)
    }

    @Test func editDetailsOpensTheBlockInline() {
        let store = makeStore()
        let d = CalDayDraft.parse(CalDayDraft.defaultPrompt, day: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal)
        store.calAddDayDraft(d, edit: true)
        #expect(store.selectedEventID == store.calendarScreen.dayDraftAddedID)
    }

    @Test func dayRowsPutNowGapAndDueInOrder() {
        let store = makeStore()
        let rows = CalDayRow.rows(day: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal)
        let ids = rows.map(\.id)
        #expect(ids.firstIndex(of: "now")! == ids.firstIndex(of: "h2")! + 1)
        #expect(ids.firstIndex(of: "gap")! > ids.firstIndex(of: "draft")!)
        #expect(ids.last == "due-due-hw6")
        guard case let .gap(start, hours) = rows.first(where: { $0.id == "gap" }) else { Issue.record("no gap"); return }
        #expect(start == Self.at(22, 18, 30))
        #expect(hours == 4.5)
        guard case let .event(_, isPast) = rows.first(where: { $0.id == "h1" }) else { return }
        #expect(isPast)
    }

    // MARK: Month

    @Test func loadBarIsBookedShareOfTheDay() {
        let store = makeStore()
        let thu = CalMonthMath.load(day: Self.thursday, events: store.events(on: Self.thursday), cal: Self.cal)
        #expect(abs(thu - (4.75 + 50.0 / 60 + 1) / 14) < 0.01)
        let sat = CalMonthMath.load(day: Self.at(24, 0), events: store.events(on: Self.at(24, 0)), cal: Self.cal)
        #expect(abs(sat - 8.0 / 14) < 0.01)
        #expect(CalMonthMath.load(day: Self.at(5, 0), events: [], cal: Self.cal) == 0)
        let allDay = CalendarEvent(title: "x", start: Self.at(5, 0), end: Self.at(5, 23), kind: .work, source: .google)
        #expect(CalMonthMath.load(day: Self.at(5, 0), events: [allDay], cal: Self.cal) == 1)
    }

    @Test func tickBarSplitsLoggedAndBooked() {
        #expect(CalMonthMath.ticks(logged: 26, booked: 13.75) == (26, 14))
        #expect(CalMonthMath.ticks(logged: 38, booked: 10) == (38, 2))
    }

    @Test func lookAheadDraftsNextWeekAndUndoes() {
        let store = makeStore()
        store.calendarScreen.monthLayers.remove(.study)
        let booked = CalMonthMath.study(month: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal).booked
        store.calDraftLookAhead()
        #expect(store.calendarScreen.monthDraftIDs.count == 4)
        #expect(store.calendarScreen.monthLayers.contains(.study))
        let drafts = store.calendarScreen.monthDraftIDs.compactMap(store.event)
        #expect(drafts.allSatisfy { $0.kind == .btDraft && $0.start >= Self.at(26, 0) && $0.start < Self.at(31, 0) })
        let after = CalMonthMath.study(month: Self.thursday, now: Self.thursday, events: store.events, cal: Self.cal).booked
        #expect(abs(after - booked - 4.75) < 0.01)
        store.calUndoLookAhead()
        #expect(store.calendarScreen.monthDraftIDs.isEmpty)
        #expect(drafts.allSatisfy { store.event($0.id) == nil })
    }
}

private extension CalDayDraft {
    var duration: TimeInterval { end.timeIntervalSince(start) }
}
