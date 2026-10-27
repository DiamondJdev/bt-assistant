import Foundation

/// BT sample data from design/screens/BT.dc.html. Times are relative to `now`.
extension SampleData {
    static func btMemories(now: Date) -> [Memory] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            Memory(id: "mem-ta", text: "TA office hours are Fri 10–11", tag: "MATH 26103", createdAt: ago(4), sourceThreadID: "today"),
            Memory(id: "mem-chem", text: "Skip the Tuesday CHEM discussion", tag: "SCHEDULE", createdAt: ago(60 * 26)),
            Memory(id: "mem-timed", text: "Prefer timed blocks over all-day reminders", tag: "CALENDAR", createdAt: ago(60 * 50)),
            Memory(id: "mem-sync", text: "Apple wins sync conflicts by default", tag: "BT-CLIENT", createdAt: ago(60 * 74), sourceThreadID: "bt-client"),
            Memory(id: "mem-work", text: "Saturday and Sunday shifts change week to week", tag: "WORK", createdAt: ago(60 * 120)),
        ]
    }

    static func btTodos(now: Date) -> [TodoItem] {
        let tonight = Calendar.bt.date(bySettingHour: 21, minute: 0, second: 0, of: now)
        return [TodoItem(id: "todo-sync", title: "Answer sync conflict question", due: tonight, projectID: "bt-client")]
    }

    static func btThreads(now: Date) -> [ChatThread] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let today = ChatThread(id: "today", title: "Today", messages: [
            Message(id: "m1", role: .user, text: "Move my HW 6 block to after CHEM SI, and remember the TA’s office hours are Friday 10–11.", time: ago(4)),
            Message(id: "m2", role: .bt, text: "Done. Moved it so there’s a 15-minute buffer after SI.", resultCards: [
                ResultCard(id: "c1", kind: .calendar, verb: .moved, title: "Discrete HW 6", detail: "2:55 → 5:15 – 6:05", deepLink: .calendar(.day, eventID: "hw6")),
                ResultCard(id: "c2", kind: .memory, verb: .saved, title: "TA office hours", detail: "Fri 10–11 · MATH 26103"),
            ], time: ago(4)),
            Message(id: "m3", role: .user, text: "How’s bt-client this week?", time: ago(2)),
            Message(id: "m4", role: .bt, insight: Insight(
                value: "5h 40m",
                sentence: "Stage 3 (Calendar sync) is 70% done. One task is waiting on you: the sync conflict question.",
                link: .code(projectID: "bt-client")
            ), time: ago(2)),
            Message(id: "m5", role: .user, text: "Add a to-do to answer it tonight. And mark DST recurrence as merged.", time: ago(1)),
            Message(id: "m6", role: .bt, resultCards: [
                ResultCard(id: "c3", kind: .todo, verb: .added, title: "Answer sync conflict question", detail: "Tonight · bt-client"),
                ResultCard(id: "c4", kind: .status, verb: .updated, title: "DST recurrence → Merged", detail: "Stage 3: 70% → 80%", deepLink: .code(projectID: "bt-client")),
            ], time: ago(1)),
        ])
        let client = ChatThread(id: "bt-client", title: "bt-client · stage 3", messages: [
            Message(role: .user, text: "What’s left in stage 3?", time: ago(121)),
            Message(role: .bt, text: "DST recurrence is in review and the sync conflict UI needs your call.", time: ago(120)),
        ], projectID: "bt-client")
        let discrete = ChatThread(id: "discrete", title: "Discrete Math", messages: [
            Message(role: .user, text: "When is HW 6 due?", time: ago(60 * 48)),
            Message(role: .bt, text: "Thursday at 11:59 PM on Blackboard.", time: ago(60 * 48)),
        ])
        let review = ChatThread(id: "week-8", title: "Week 8 review", messages: [
            Message(role: .user, text: "How did last week go?", time: ago(60 * 96)),
            Message(role: .bt, text: "You logged 9 hours of focus and missed one study block.", time: ago(60 * 96)),
        ])
        return [today, client, discrete, review]
    }

    /// Undo tokens point at real sample data. The prototype's sixth entry ("Set 4 × 25 cycle",
    /// kind FOCUS) is left out: `ResultKind` has no focus case.
    static func btLedger(now: Date, events: [CalendarEvent], projects: [Project]) -> [LedgerEntry] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let stage3 = projects.first { $0.id == "bt-client" }?.stages.first { $0.id == "s3" }
        let hw6 = events.first { $0.id == "hw6" }
        let entries: [LedgerEntry?] = [
            stage3.map { LedgerEntry(id: "l4", time: ago(1), kind: .status, summary: "DST recurrence → Merged",
                                     undo: .restoreStage(projectID: "bt-client", stage: $0), resultCardID: "c4") },
            LedgerEntry(id: "l3", time: ago(1), kind: .todo, summary: "Answer sync conflict question",
                        undo: .removeTodo(id: "todo-sync"), resultCardID: "c3"),
            LedgerEntry(id: "l2", time: ago(4), kind: .memory, summary: "TA office hours · Fri 10–11",
                        undo: .removeMemory(id: "mem-ta"), resultCardID: "c2"),
            hw6.map { LedgerEntry(id: "l1", time: ago(4), kind: .calendar, summary: "HW 6 block moved to 5:15",
                                  undo: .restoreEvent($0), resultCardID: "c1") },
            LedgerEntry(id: "l0", time: ago(228), kind: .calendar, summary: "Added bt-client deep work, Fri 1–3",
                        undo: .removeEvent(id: "f2")),
        ]
        return entries.compactMap { $0 }
    }

}
