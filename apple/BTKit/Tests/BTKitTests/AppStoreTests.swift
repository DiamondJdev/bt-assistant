import Foundation
import Testing
@testable import BTKit

@MainActor
struct AppStoreTests {
    /// Thursday 22 Oct 2026, 12:46.
    static let thursday = Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 46))!

    func makeStore() -> AppStore {
        AppStore(clock: { Self.thursday })
    }

    @Test func tickCountsDownAndAddsFocusedTime() {
        let store = makeStore()
        let left = store.focus.remainingSeconds
        let focused = store.focusedTodaySeconds
        store.tick()
        #expect(store.focus.remainingSeconds == left - 1)
        #expect(store.focusedTodaySeconds == focused + 1)
    }

    @Test func pausedTickDoesNothing() {
        let store = makeStore()
        store.toggleFocusPause()
        let left = store.focus.remainingSeconds
        store.tick()
        #expect(store.focus.remainingSeconds == left)
    }

    @Test func addFiveMinutesGrowsLeftAndTotal() {
        let store = makeStore()
        let (left, total) = (store.focus.remainingSeconds, store.focus.plannedSeconds)
        store.addFiveMinutes()
        #expect(store.focus.remainingSeconds == left + 300)
        #expect(store.focus.plannedSeconds == total + 300)
    }

    @Test func endingSessionLogsFocusBlockAndStartsBreak() {
        let store = makeStore()
        let logged = store.events.filter { $0.kind == .focusLogged }.count
        store.endOrStartNext()
        #expect(store.focus.mode == .break)
        #expect(store.focus.remainingSeconds == 300)
        #expect(store.events.filter { $0.kind == .focusLogged }.count == logged + 1)
    }

    @Test func timerReachingZeroStartsBreak() {
        let store = makeStore()
        store.focus.remainingSeconds = 1
        store.tick()
        #expect(store.focus.mode == .break)
    }

    @Test func breakThenStartNextReturnsToFocus() {
        let store = makeStore()
        let number = store.focus.number
        store.endOrStartNext()
        store.endOrStartNext()
        #expect(store.focus.mode == .focus)
        #expect(store.focus.number == number + 1)
        #expect(store.focus.remainingSeconds == 1500)
    }

    @Test func startFocusFromEventUsesPlanAndTitle() {
        let store = makeStore()
        let event = store.event("f2")!
        store.startFocus(from: event)
        #expect(store.route == .focus)
        #expect(store.focus.taskTitle == "bt-client deep work")
        #expect(store.focus.plannedSeconds == 50 * 60)
    }

    @Test func sessionMinutesParsesPlans() {
        #expect(AppStore.sessionMinutes("50/10") == 50)
        #expect(AppStore.sessionMinutes("2×25") == 25)
        #expect(AppStore.sessionMinutes("soon") == nil)
    }

    @Test func undoRemovesMemoryAndMarksCard() {
        let store = makeStore()
        let card = ResultCard(kind: .memory, verb: .saved, title: "TA hours", detail: "Fri")
        let memory = Memory(text: "TA hours", tag: "MATH")
        store.memories.append(memory)
        store.threads[0].messages.append(Message(role: .bt, resultCards: [card]))
        let entry = LedgerEntry(kind: .memory, summary: "TA hours", undo: .removeMemory(id: memory.id), resultCardID: card.id)
        store.record(entry)

        store.undo(entry.id)

        #expect(!store.memories.contains(memory))
        #expect(store.ledger[0].isUndone)
        #expect(store.threads[0].messages.last?.resultCards[0].isUndone == true)
    }

    @Test func undoRestoresMovedEvent() {
        let store = makeStore()
        let original = store.event("hw6")!
        var moved = original
        moved.start.addTimeInterval(3600)
        store.updateEvent(moved)
        let entry = LedgerEntry(kind: .calendar, summary: "moved", undo: .restoreEvent(original))
        store.record(entry)

        store.undo(entry.id)

        #expect(store.event("hw6") == original)
    }

    @Test func askAboutProjectOpensScopedThread() {
        let store = makeStore()
        store.open(.bt(projectID: "mirai"))
        #expect(store.route == .bt)
        #expect(store.thread(store.selectedThreadID)?.projectID == "mirai")
        let count = store.threads.count
        store.open(.bt(projectID: "mirai"))
        #expect(store.threads.count == count)
    }

    @Test func sampleTodayHasThursdayClasses() {
        let store = makeStore()
        let titles = store.events(on: Self.thursday).map(\.title)
        #expect(titles.contains("MATH 26103 · Discrete Math"))
        #expect(store.nextEventToday?.title == "MATH 26103 · Discrete Math")
    }

    @Test func gridRowsHonorMinimums() {
        let grid = SandGrid(rows: [1, 1], minRowHeights: [300, 0])
        #expect(grid.rowHeights(total: 400) == [300, 100])
        #expect(grid.rowHeights(total: 800) == [400, 400])
    }
}
