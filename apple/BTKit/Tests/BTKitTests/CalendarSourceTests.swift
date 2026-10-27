import EventKit
import Foundation
import Testing
@testable import BTKit

@MainActor
struct CalendarSourceTests {
    static let thursday = AppStoreTests.thursday

    @Test func eventKitMetadataSuppliesWeeklyCardDetails() {
        let eventStore = EKEventStore()
        let item = EKEvent(eventStore: eventStore)
        let sourceCalendar = EKCalendar(for: .event, eventStore: eventStore)
        sourceCalendar.title = "UARK"
        item.calendar = sourceCalendar
        item.title = "Lab"
        item.startDate = Self.thursday
        item.endDate = Self.thursday.addingTimeInterval(3600)
        item.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday), EKRecurrenceDayOfWeek(.thursday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil)]
        let event = CalendarEvent(item)
        #expect(event.calendarTitle == "UARK")
        #expect(!event.hasAttendees)
        #expect(event.recurrenceSummary == "Every Tue, Thu")
        #expect(CalWeekKind.classify(event) == .classSession)
        #expect(CalendarEvent.recurrenceSummary([]) == nil)
        #expect(CalendarEvent.recurrenceSummary([EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)]) == "Every 2 days")
    }

    private func event(_ id: String, hour: Double, kind: EventKind = .classSession) -> CalendarEvent {
        let start = Self.thursday.addingTimeInterval((hour - 12.75) * 3600)
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(3600), kind: kind, source: .apple)
    }

    private func makeStore(_ source: FakeCalendarSource) -> AppStore {
        AppStore(clock: { Self.thursday }, calendarSource: source)
    }

    @Test func storeShowsSourceEventsInsteadOfSamples() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 9)])
        let store = makeStore(source)
        #expect(store.events.map(\.id) == ["ek:a@1"])
        #expect(store.calendarStatus == "Calendar — synced 12:46")
    }

    @Test func addSavesThroughTheSource() {
        let source = FakeCalendarSource([])
        let store = makeStore(source)
        store.addEvent(event("new", hour: 15, kind: .studyPlanned))
        #expect(source.events.map(\.id) == ["new"])
        #expect(store.event("new") != nil)
    }

    @Test func updateFollowsANewIdentifierFromTheSource() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 9)])
        source.renameOnSave = "ek:b@1"
        let store = makeStore(source)
        store.selectedEventID = "ek:a@1"
        var moved = store.events[0]
        moved.title = "Moved"
        store.updateEvent(moved)
        #expect(store.events.map(\.id) == ["ek:b@1"])
        #expect(store.selectedEventID == "ek:b@1")
        #expect(source.events.first?.title == "Moved")
    }

    @Test func deleteRemovesFromTheSource() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 9)])
        let store = makeStore(source)
        store.deleteEvent("ek:a@1")
        #expect(source.events.isEmpty)
        #expect(store.events.isEmpty)
    }

    @Test func draftsStayLocalAndSurviveAReload() {
        let source = FakeCalendarSource([])
        let store = makeStore(source)
        store.addEvent(event("draft-1", hour: 18, kind: .btDraft))
        source.changeToken += 1
        store.tick()
        #expect(source.events.isEmpty)
        #expect(store.events.map(\.id) == ["draft-1"])
    }

    @Test func tickReloadsWhenTheSourceChanges() {
        let source = FakeCalendarSource([])
        let store = makeStore(source)
        source.events = [event("ek:x@1", hour: 16)]
        source.changeToken += 1
        store.tick()
        #expect(store.events.map(\.id) == ["ek:x@1"])
    }

    @Test func failedSaveShowsTheErrorAndRestoresTheSource() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 9)])
        let store = makeStore(source)
        source.failSaves = true
        var moved = store.events[0]
        moved.title = "Moved"
        store.updateEvent(moved)
        #expect(store.events.first?.title == "ek:a@1")
        #expect(store.calendarStatus == "Calendar couldn’t save: read-only")
    }

    @Test func noAccessSaysSo() {
        let source = FakeCalendarSource([])
        source.hasAccess = false
        #expect(makeStore(source).calendarStatus == "Calendar access is off")
    }

    // MARK: All-day events

    private func allDay(_ id: String, days: Int, from start: Date) -> CalendarEvent {
        let day = Calendar.bt.startOfDay(for: start)
        return CalendarEvent(id: id, title: id, start: day, end: day + Double(days * 86_400) - 1, kind: .classSession,
                             source: .apple, isAllDay: true)
    }

    @Test func allDayEventsShowOnEveryDayTheyCoverAndBlockNoTime() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 9), allDay("Fall break", days: 2, from: Self.thursday)])
        let store = makeStore(source)
        let friday = Self.thursday + 86_400
        #expect(store.events.map(\.id) == ["ek:a@1"])
        #expect(store.allDayEvents(on: Self.thursday).map(\.title) == ["Fall break"])
        #expect(store.allDayEvents(on: friday).map(\.title) == ["Fall break"])
        #expect(store.allDayEvents(on: friday + 86_400).isEmpty)
        #expect(store.calNextFreeSlot(after: Self.thursday) == Calendar.bt.date(bySettingHour: 13, minute: 0, second: 0, of: Self.thursday))
    }

    @Test func todayListsAllDayEventsFirst() {
        let source = FakeCalendarSource([event("ek:a@1", hour: 15), allDay("Fall break", days: 1, from: Self.thursday)])
        let rows = makeStore(source).todayAgenda
        #expect(rows.first?.time == "ALL DAY")
        #expect(rows.first?.title == "Fall break")
    }

    @Test func allDayRoundTripsThroughEventKit() {
        let e = allDay("Fall break", days: 1, from: Self.thursday)
        let ek = EKEvent(eventStore: EKEventStore())
        e.apply(to: ek)
        #expect(ek.isAllDay)
        #expect(CalendarEvent(ek, source: .apple).isAllDay)
    }

    // MARK: EventKit mapping

    @Test func btFieldsRoundTripThroughTheEventURL() throws {
        var e = event("abc", hour: 15, kind: .studyPlanned)
        e.runAsFocus = true
        e.focusPlan = "2×25"
        e.linkedProjectID = "bt-client"
        let ek = EKEvent(eventStore: EKEventStore())
        e.apply(to: ek)
        let back = CalendarEvent(ek, source: .apple)
        #expect(back.id == "abc")
        #expect(back.kind == .studyPlanned && back.source == .bt)
        #expect(back.runAsFocus && back.focusPlan == "2×25" && back.linkedProjectID == "bt-client")
        #expect(back.title == "abc" && back.start == e.start && back.end == e.end)
    }

    @Test func plainEventsGetAnEventKitIDAndAGuessedKind() {
        let ek = EKEvent(eventStore: EKEventStore())
        ek.title = "Dentist"
        ek.startDate = Self.thursday
        ek.endDate = Self.thursday.addingTimeInterval(1800)
        let e = CalendarEvent(ek, source: .google)
        #expect(e.id.hasPrefix("ek:"))
        #expect(CalendarEvent.eventKitID(e.id)?.occurrenceStart == Self.thursday)
        #expect(e.kind == .classSession && e.source == .google)
    }

    @Test func applyKeepsSomeoneElsesURL() {
        let ek = EKEvent(eventStore: EKEventStore())
        let zoom = URL(string: "https://zoom.us/j/1")!
        ek.url = zoom
        event("abc", hour: 9).apply(to: ek)
        #expect(ek.url == zoom)
    }

    @Test func accountTitleNamesTheSource() {
        #expect(CalendarEvent.source(accountTitle: "me@gmail.com") == .google)
        #expect(CalendarEvent.source(accountTitle: "Google") == .google)
        #expect(CalendarEvent.source(accountTitle: "iCloud") == .apple)
    }
}

@MainActor
final class FakeCalendarSource: CalendarSource {
    var events: [CalendarEvent]
    var changeToken = 0
    var hasAccess = true
    var failSaves = false
    var failDeletes = false
    var renameOnSave: String?

    init(_ events: [CalendarEvent]) { self.events = events }

    func events(in interval: DateInterval) -> [CalendarEvent] {
        events.filter { interval.contains($0.start) }
    }

    func save(_ event: CalendarEvent) throws -> CalendarEvent {
        if failSaves { throw ToolError.failed("read-only") }
        var saved = event
        if let renameOnSave { saved.id = renameOnSave }
        events.removeAll { $0.id == event.id }
        events.append(saved)
        return saved
    }

    func delete(_ event: CalendarEvent) throws {
        if failDeletes { throw ToolError.failed("read-only") }
        events.removeAll { $0.id == event.id }
    }
}
