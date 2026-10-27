import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct NativeReviewRegressionTests {
    let start = AppStoreTests.thursday

    func block(_ title: String) -> CalendarEvent {
        CalendarEvent(title: title, start: start, end: start + 1500, kind: .studyPlanned, source: .bt)
    }

    @Test func failedSuggestionCanBeRetried() throws {
        let source = FakeCalendarSource([])
        let store = AppStore(clock: { start }, calendarSource: source)
        let project = try #require(store.projects.first)
        let suggestion = CodeSuggestion(title: "Book", label: "Add", doneLabel: "Added",
            action: .book(start: start, end: start + 1500, title: "Work"))
        source.failSaves = true
        store.acceptCodeSuggestion(suggestion, slot: 0, projectID: project.id)
        #expect(store.code.accepted[project.id]?[0] == nil)
        #expect(source.events.isEmpty)
        source.failSaves = false
        store.acceptCodeSuggestion(suggestion, slot: 0, projectID: project.id)
        #expect(store.code.accepted[project.id]?[0] == suggestion)
        #expect(source.events.count == 1)
    }

    @Test func todaySaveAndUndoFailuresKeepRetryState() throws {
        let source = FakeCalendarSource([])
        let store = AppStore(clock: { start }, calendarSource: source)
        let ledgerCount = store.ledger.count
        source.failSaves = true
        store.bookTodaySession()
        #expect(store.ledger.count == ledgerCount)
        #expect(store.today.bookedEventID == nil)
        #expect(store.today.bookedLedgerID == nil)
        source.failSaves = false
        source.renameOnSave = "saved-booking"
        store.bookTodaySession()
        let booked = try #require(store.todayBookedEvent)
        #expect(booked.id == "saved-booking")
        let ledgerID = try #require(store.today.bookedLedgerID)
        #expect(store.ledger.first?.undo == .removeEvent(id: booked.id))
        source.failDeletes = true
        store.undoTodayBooking()
        #expect(store.today.bookedEventID == booked.id)
        #expect(store.today.bookedLedgerID == ledgerID)
        #expect(store.ledger.first?.isUndone == false)
        source.failDeletes = false
        store.undoTodayBooking()
        #expect(store.today.bookedEventID == nil)
        #expect(store.today.bookedLedgerID == nil)
        #expect(store.event(booked.id) == nil)
        #expect(store.ledger.first?.isUndone == true)
    }

    @Test func todayUndoWithoutLedgerCanRetryDelete() {
        let event = block("Booking")
        let source = FakeCalendarSource([event])
        let store = AppStore(clock: { start }, calendarSource: source)
        store.today.bookedEventID = event.id
        source.failDeletes = true
        store.undoTodayBooking()
        #expect(store.today.bookedEventID == event.id)
        source.failDeletes = false
        store.undoTodayBooking()
        #expect(store.today.bookedEventID == nil)
        #expect(store.event(event.id) == nil)
    }

    @Test(arguments: ["delete", "update", "add"])
    func failedUndoKeepsLedgerAndCardForRetry(operation: String) {
        let original = block("Original")
        var moved = original
        moved.title = "Moved"
        let source = FakeCalendarSource(operation == "add" ? [] : [moved])
        let store = AppStore(clock: { start }, calendarSource: source)
        let card = ResultCard(kind: .calendar, verb: .saved, title: "Change", detail: "")
        store.threads[0].messages.append(Message(role: .bt, resultCards: [card]))
        let entry = LedgerEntry(kind: .calendar, summary: "Change",
            undo: operation == "delete" ? .removeEvent(id: original.id) : .restoreEvent(original), resultCardID: card.id)
        store.record(entry)
        source.failSaves = true
        source.failDeletes = true
        store.undo(entry.id)
        #expect(store.ledger.first?.isUndone == false)
        #expect(store.threads[0].messages.last?.resultCards[0].isUndone == false)
        #expect(store.events == (operation == "add" ? [] : [moved]))
        source.failSaves = false
        source.failDeletes = false
        store.undo(entry.id)
        #expect(store.ledger.first?.isUndone == true)
        #expect(store.threads[0].messages.last?.resultCards[0].isUndone == true)
        #expect(store.events == (operation == "delete" ? [] : [original]))
    }

    @Test func switchingFocusPreservesPreviousLabel() throws {
        let container = try ModelContainer(for: FocusSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = TestClock(start)
        let timer = PomodoroModule(modelContext: container.mainContext,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, notifier: FakeNotifier(), now: { clock.now })
        let store = AppStore(clock: { clock.now }, pomodoro: timer)
        store.startFocus(from: block("A"))
        clock.now += 120
        store.startFocus(from: block("B"))
        let sessions = timer.loggedSessions(in: DateInterval(start: start, end: start + 3600))
        #expect(sessions.count == 1)
        #expect(sessions.first?.label == "A")
        #expect(sessions.first?.0.end == start + 120)
        #expect(timer.label == "B")
        #expect(timer.state.isRunning)
    }

    @Test func focusCompletionReattributesUnchangedCodingActivity() throws {
        let container = try ModelContainer(for: FocusSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = TestClock(start)
        let timer = PomodoroModule(modelContext: container.mainContext,
            defaults: UserDefaults(suiteName: UUID().uuidString)!, notifier: FakeNotifier(), now: { clock.now })
        let source = FakeCodeSource([Project(id: "repo", name: "Repo", path: "", stack: "swift", activity: [
            CodingActivity(start: start, end: start + 120, projectID: "repo", source: .manual)
        ])])
        let store = AppStore(clock: { clock.now }, pomodoro: timer, codeSource: source)
        #expect(store.projects[0].activity[0].insideFocusSessionID == nil)
        store.startFocus(from: block("A"))
        clock.now += 1500
        store.tick()
        #expect(source.changeToken == 0)
        #expect(store.projects[0].activity[0].insideFocusSessionID != nil)
    }

    @Test func macShellRefreshesCalendarOnActivation() throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: apple.appendingPathComponent("BTMac/BTMacApp.swift"), encoding: .utf8)
        let activation = try #require(source.range(of: ".onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))"))
        let body = source[activation.upperBound...].prefix { $0 != "}" }
        #expect(body.contains("refreshAccess()"))
        #expect(body.contains("store.tick()"))
    }
}
