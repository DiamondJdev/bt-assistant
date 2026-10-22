import Foundation

/// BT sample data from design/screens/BT.dc.html.
extension SampleData {
    static func btMemories(now: Date) -> [Memory] { [] }
    static func btTodos(now: Date) -> [TodoItem] { [] }
    static func btThreads(now: Date) -> [ChatThread] { [ChatThread(id: "today", title: "Today")] }
    static func btLedger(now: Date) -> [LedgerEntry] { [] }
}
