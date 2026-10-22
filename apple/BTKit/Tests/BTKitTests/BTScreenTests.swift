import Foundation
import Testing
@testable import BTKit

@MainActor
struct BTScreenTests {
    /// Thursday 22 Oct 2026, 12:46.
    static let thursday = Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 46))!

    func makeStore() -> AppStore { AppStore(clock: { Self.thursday }) }

    /// Sends `text` in the Today thread and returns BT's reply.
    func send(_ text: String, _ store: AppStore, thread: String = "today") -> Message {
        store.sendToBT(text, threadID: thread)
        return store.thread(thread)!.messages.last!
    }

    // MARK: Routing

    @Test(arguments: [
        ("/remember the lab is in room 210", BTIntent.memory),
        ("Remember that I hate 8 AMs", .memory),
        ("/todo email the TA", .todo),
        ("add a to-do to buy flasks", .todo),
        ("/block CHEM review", .calendar),
        ("book an hour for HIST reading", .calendar),
        ("schedule lab prep", .calendar),
        ("move my HW block", .calendar),
        ("/status DST recurrence merged", .status),
        ("mark DST recurrence as merged", .status),
        ("@code today", .insight),
        ("what did I do today?", .insight),
        ("thanks", .fallback),
    ])
    func routesByKeyword(text: String, intent: BTIntent) {
        #expect(BTIntent.route(text) == intent)
    }

    @Test func bodyStripsCommandWords() {
        #expect(BTIntent.body("/remember the lab is in room 210") == "The lab is in room 210")
        #expect(BTIntent.body("add a to-do to buy flasks.") == "Buy flasks")
        #expect(BTIntent.body("/todo") == "New item")
    }

    // MARK: Writes produce a card and a ledger entry; undo reverts them

    @Test func memoryWriteAndUndo() throws {
        let store = makeStore()
        let reply = send("/remember the lab is in room 210", store)
        let card = try #require(reply.resultCards.first)
        let entry = store.ledger[0]
        #expect(card.kind == .memory && entry.resultCardID == card.id)
        guard case let .removeMemory(id) = entry.undo else { Issue.record("wrong token"); return }
        let memory = try #require(store.memories.first { $0.id == id })
        #expect(memory.text == "The lab is in room 210" && memory.sourceThreadID == "today" && memory.tag == "FROM CHAT")

        store.undo(entry.id)
        #expect(!store.memories.contains { $0.id == id })
        #expect(store.thread("today")!.messages.last!.resultCards[0].isUndone)
    }

    @Test func todoWriteAndUndo() throws {
        let store = makeStore()
        let card = try #require(send("/todo email the TA", store).resultCards.first)
        let entry = store.ledger[0]
        #expect(card.kind == .todo && entry.resultCardID == card.id)
        guard case let .removeTodo(id) = entry.undo else { Issue.record("wrong token"); return }
        #expect(store.todos.contains { $0.id == id && $0.title == "Email the TA" })
        store.undo(entry.id)
        #expect(!store.todos.contains { $0.id == id })
    }

    @Test func calendarBooksEveningStudyBlockAndUndo() throws {
        let store = makeStore()
        let card = try #require(send("/block CHEM review", store).resultCards.first)
        let entry = store.ledger[0]
        guard case let .removeEvent(id) = entry.undo else { Issue.record("wrong token"); return }
        let event = try #require(store.event(id))
        #expect(card.deepLink == .calendar(.week, eventID: id) && entry.resultCardID == card.id)
        #expect(event.kind == .studyPlanned && event.runAsFocus && event.focusPlan == "2×25")
        #expect(store.calendar.component(.hour, from: event.start) == 19)
        #expect(store.calendar.isDate(event.start, inSameDayAs: Self.thursday))

        store.undo(entry.id)
        #expect(store.event(id) == nil)
    }

    @Test func eveningSlotSkipsBusyTime() {
        let store = makeStore()
        let first = store.nextEveningSlot()
        store.addEvent(CalendarEvent(title: "Busy", start: first, end: first.addingTimeInterval(3600), kind: .work, source: .google))
        #expect(store.nextEveningSlot() == first.addingTimeInterval(3600))
    }

    @Test func statusMarksTaskDoneAndUndoRestoresStage() throws {
        let store = makeStore()
        let before = store.project("bt-client")!.stages.first { $0.id == "s3" }!
        let card = try #require(send("mark DST recurrence as merged", store).resultCards.first)
        let stage = store.project("bt-client")!.stages.first { $0.id == "s3" }!
        #expect(stage.tasks.first { $0.id == "t3" }?.status == .done)
        #expect(stage.progress > before.progress)
        #expect(card.title == "DST recurrence → Merged" && card.deepLink == .code(projectID: "bt-client"))
        #expect(store.ledger[0].undo == .restoreStage(projectID: "bt-client", stage: before))

        store.undo(store.ledger[0].id)
        #expect(store.project("bt-client")!.stages.first { $0.id == "s3" } == before)
    }

    @Test func unknownStatusTaskWritesNothing() {
        let store = makeStore()
        let count = store.ledger.count
        let reply = send("mark the moon landing as merged", store)
        #expect(reply.resultCards.isEmpty && store.ledger.count == count)
    }

    // MARK: Reads

    @Test func insightTotalsTodaysCoding() throws {
        let store = makeStore()
        let insight = try #require(send("@code how am I doing", store).insight)
        #expect(insight.value == "3h 12m")
        #expect(insight.link == .code(projectID: nil))
        #expect(store.ledger.count == SampleData(now: Self.thursday).ledger.count)
    }

    @Test func insightIsScopedToThreadProject() throws {
        let store = makeStore()
        let insight = try #require(send("how is it going?", store, thread: "bt-client").insight)
        #expect(insight.value == "1h 48m")
        #expect(insight.link == .code(projectID: "bt-client"))
    }

    @Test func projectThreadMemoryTagsProject() {
        let store = makeStore()
        _ = send("remember Apple wins", store, thread: "bt-client")
        #expect(store.memories.last?.tag == "BT-CLIENT")
    }

    @Test func fallbackRepliesWithText() {
        let store = makeStore()
        let reply = send("thanks", store)
        #expect(reply.role == .bt && reply.text != nil && reply.resultCards.isEmpty)
    }

    @Test func newThreadIsEmptyAndSelected() {
        let store = makeStore()
        store.newBTThread()
        #expect(store.thread(store.selectedThreadID)?.messages.isEmpty == true)
    }

    // MARK: Sample data

    @Test func sampleLedgerUndoTokensReferenceSampleData() {
        let store = makeStore()
        let cardIDs = Set(store.threads.flatMap(\.messages).flatMap(\.resultCards).map(\.id))
        #expect(store.ledger.count == 5)
        for entry in store.ledger {
            if let cardID = entry.resultCardID { #expect(cardIDs.contains(cardID)) }
            switch entry.undo {
            case .removeEvent(let id): #expect(store.event(id) != nil)
            case .restoreEvent(let event): #expect(store.event(event.id) == event)
            case .removeMemory(let id): #expect(store.memories.map(\.id).contains(id))
            case .removeTodo(let id): #expect(store.todos.map(\.id).contains(id))
            case let .restoreStage(projectID, stage):
                let current = store.project(projectID)?.stages.first { $0.id == stage.id }
                #expect(current == stage)
            }
        }
    }

    @Test func newestSampleMemoryIsTAOfficeHours() {
        let newest = makeStore().memories.max { $0.createdAt < $1.createdAt }
        #expect(newest?.text == "TA office hours are Fri 10–11")
    }

    @Test func undoingSampleEntriesRevertsAndMarksCards() {
        let store = makeStore()
        for entry in store.ledger { store.undo(entry.id) }
        let allUndone = store.ledger.allSatisfy(\.isUndone)
        #expect(allUndone)
        #expect(store.memories.count == 4 && store.todos.isEmpty && store.event("f2") == nil)
        let cards = store.thread("today")!.messages.flatMap(\.resultCards)
        let cardsUndone = cards.allSatisfy(\.isUndone)
        #expect(cardsUndone)
    }
}
