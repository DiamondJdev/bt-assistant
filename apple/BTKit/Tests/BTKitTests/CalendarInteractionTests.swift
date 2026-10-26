import Foundation
import Testing
@testable import BTKit

@MainActor
struct CalendarInteractionTests {
    private static let cal = CalendarScreenTests.cal
    private static let now = CalendarScreenTests.thursday

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        CalendarScreenTests.at(day, hour, minute)
    }

    private func event(kind: EventKind = .studyPlanned) -> CalendarEvent {
        CalendarEvent(title: "Study", start: at(22, 10, 15), end: at(22, 10, 50), kind: kind, source: .bt)
    }

    @Test func newEventStaysOnSelectedDayUntilSaved() throws {
        let store = AppStore(clock: { Self.now })
        store.calendarDate = at(25, 0)
        store.calendarMode = .month
        let before = store.events
        let created = store.calNewEvent()
        #expect(Self.cal.isDate(created.start, inSameDayAs: at(25, 0)))
        #expect(store.events == before)
        #expect(store.calendarMode == .month)
        let draft = try #require(store.calendarScreen.eventEditor)
        #expect(draft.isNew)
        #expect(store.calSaveEditor(draft))
        #expect(store.event(created.id) != nil)
    }

    @Test func cancellingCreationAndEditingDoesNotWrite() throws {
        let source = FakeCalendarSource([event()])
        let store = AppStore(clock: { Self.now }, calendarSource: source)
        let before = source.events
        store.calNewEvent()
        store.calCancelEditor()
        #expect(source.events == before)
        store.calSelect(before[0].id)
        var draft = try #require(store.calendarScreen.eventEditor)
        draft.event.title = "Unsaved"
        draft.moveStart(to: at(22, 11))
        store.calCancelEditor()
        #expect(source.events == before)
        #expect(store.events == before)
        #expect(store.selectedEventID == nil)
    }

    @Test func customTimesPreserveDurationAndSaveOnlyOnConfirmation() throws {
        let original = event()
        let store = AppStore(clock: { Self.now }, calendarSource: FakeCalendarSource([original]))
        store.calSelect(original.id)
        var draft = try #require(store.calendarScreen.eventEditor)
        draft.moveStart(to: at(23, 10, 15))
        #expect(draft.event.end == at(23, 10, 50))
        draft.event.end = at(23, 11, 20)
        #expect(draft.event.duration == 65 * 60)
        #expect(store.event(original.id) == original)
        #expect(store.calSaveEditor(draft))
        #expect(store.event(original.id)?.end == at(23, 11, 20))
        #expect(store.calendarScreen.eventEditor == nil)
        #expect(store.calendarDate == at(23, 10, 15))
    }

    @Test func durationPresetsAndInvalidRanges() {
        var draft = CalEventDraft(event: event(), isNew: true)
        for minutes in [15, 30, 45, 60, 90] {
            draft.setDuration(minutes: minutes)
            #expect(draft.event.duration == Double(minutes * 60))
        }
        let store = AppStore(clock: { Self.now })
        draft.event.end = draft.event.start
        #expect(!draft.isValid)
        #expect(!store.calSaveEditor(draft))
        draft.event.end = draft.event.start.addingTimeInterval(-60)
        #expect(!draft.isValid)
        draft.setDuration(minutes: 35)
        draft.event.title = "  \n "
        #expect(!draft.isValid)
    }

    @Test func failedSaveLeavesDraftOpenAndSourceUnchanged() throws {
        let original = event()
        let source = FakeCalendarSource([original])
        let store = AppStore(clock: { Self.now }, calendarSource: source)
        store.calSelect(original.id)
        var draft = try #require(store.calendarScreen.eventEditor)
        draft.event.end = at(22, 11, 20)
        source.failSaves = true
        #expect(!store.calSaveEditor(draft))
        #expect(store.calendarScreen.eventEditor != nil)
        #expect(source.events == [original])
        #expect(store.calendarError != nil)
    }

    @Test func saveUsesTheSourcesNewIdentifier() throws {
        let original = event()
        let source = FakeCalendarSource([original])
        let store = AppStore(clock: { Self.now }, calendarSource: source)
        store.calSelect(original.id)
        let draft = try #require(store.calendarScreen.eventEditor)
        source.renameOnSave = "renamed-occurrence"
        #expect(store.calSaveEditor(draft))
        #expect(store.event("renamed-occurrence") != nil)
        #expect(store.event(original.id) == nil)
        #expect(store.calendarScreen.eventEditor == nil)
    }

    @Test func deepLinkUsesSharedEditorAndSaveStartsUpdatedFocus() throws {
        let original = event()
        let source = FakeCalendarSource([original])
        let store = AppStore(clock: { Self.now }, calendarSource: source)
        store.open(.calendar(.day, date: nil, eventID: original.id))
        var draft = try #require(store.calendarScreen.eventEditor)
        draft.event.title = "Updated study"
        source.failSaves = true
        #expect(!store.calSaveEditor(draft, startFocus: true))
        #expect(store.route == .calendar)
        source.failSaves = false
        source.renameOnSave = "saved-focus"
        #expect(store.calSaveEditor(draft, startFocus: true))
        #expect(store.route == .focus)
        #expect(store.focus.taskTitle == "Updated study")
        #expect(store.event("saved-focus")?.title == "Updated study")
    }

    @Test func focusHistoryPreferencePersistsWithoutHidingPlannedFocus() throws {
        let name = "CalendarInteractionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = CalendarScreenState(defaults: defaults)
        let planned = event()
        let logged = event(kind: .focusLogged)
        #expect(!state.showFocusHistory)
        #expect(state.planningEvents([planned, logged]) == [planned])
        state.showFocusHistory = true
        #expect(state.planningEvents([planned, logged]) == [planned, logged])
        #expect(CalendarScreenState(defaults: defaults).showFocusHistory)
        state.showFocusHistory = false
        #expect(!CalendarScreenState(defaults: defaults).showFocusHistory)
    }

    @Test func loggedFocusDoesNotConsumePlannedTime() {
        let planned = event()
        let logged = event(kind: .focusLogged)
        let hours = CalHoursBreakdown(day: Self.now, events: [planned, logged], cal: Self.cal)
        #expect(abs(hours.focusHours - 35.0 / 60) < 0.001)
        let plannedLoad = CalMonthMath.load(day: Self.now, events: [planned], cal: Self.cal)
        #expect(CalMonthMath.load(day: Self.now, events: [planned, logged], cal: Self.cal) == plannedLoad)
    }

    @Test func allDaySelectionOpensReadOnlyDetails() throws {
        let store = AppStore(clock: { Self.now })
        var allDay = event()
        allDay.isAllDay = true
        store.allDayEvents = [allDay]
        store.calSelect(allDay.id)
        let draft = try #require(store.calendarScreen.eventEditor)
        #expect(draft.event == allDay)
        #expect(!draft.isEditable)
        #expect(!store.calSaveEditor(draft))
    }

    @Test func loggedFocusDoesNotBlockDraftScheduling() {
        let logged = CalendarEvent(title: "History", start: at(22, 8), end: at(22, 22), kind: .focusLogged, source: .focus)
        let store = AppStore(clock: { Self.now })
        store.events = [logged]
        #expect(store.calNextFreeSlot(after: at(22, 8)) == at(22, 8))
        let draft = CalDayDraft.parse("35m Study", day: at(22, 0), now: at(24, 12), events: [logged], cal: Self.cal)
        #expect(draft.start == at(22, 8))
        #expect(draft.end == at(22, 8, 35))
    }

    @Test func todayCollapsesEarlierAndSeparatesDeadlines() {
        let past = event()
        let upcoming = CalendarEvent(title: "Next", start: at(22, 15), end: at(22, 16), kind: .work, source: .apple)
        let due = CalendarEvent(title: "Due", start: at(22, 23), end: at(22, 23, 59), kind: .deadline, source: .blackboard)
        let sections = CalDaySections(day: Self.now, now: Self.now, events: [past, upcoming, due], cal: Self.cal)
        #expect(sections.earlier.map(\.id) == [past.id])
        #expect(sections.deadlines == [due])
        #expect(!sections.upcoming.contains { $0.id == past.id || $0.id == "due-" + due.id })
        #expect(sections.upcoming.contains { $0.id == "now" })
        let otherDay = CalDaySections(day: Self.now, now: at(24, 12), events: [past, upcoming, due], cal: Self.cal)
        #expect(otherDay.earlier.isEmpty)
        #expect(otherDay.upcoming.contains { $0.id == past.id })
    }
}
