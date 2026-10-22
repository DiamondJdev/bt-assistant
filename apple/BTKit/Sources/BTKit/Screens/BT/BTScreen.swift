import SwiftUI

/// BT chat: threads and memory, the conversation, and the ledger of changes BT made.
public struct BTScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        SandGrid(columns: 4, rows: [1]) {
            BTThreadsColumn(store: store)
                .dashedEdges(bottom: false)
                .gridCell(0, 0)
            BTConversation(store: store)
                .dashedEdges(bottom: false)
                .gridCell(1, 0, columns: 2)
            BTLedgerColumn(store: store)
                .gridCell(3, 0)
        }
    }
}

extension AppStore {
    /// Opens a fresh, empty thread (⌘N).
    func newBTThread() {
        let thread = ChatThread(title: "New thread")
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }
}

/// Column 4 of the header while BT is open: "Focus running · next Discrete Math 1:30".
public struct BTHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        HStack(spacing: 6) {
            link(focusLabel) { store.open(.focus) }
            if let next = store.nextEventToday {
                Text("·")
                link("next \(Self.shortTitle(next.title)) \(BTFormat.clock(next.start, store.calendar))") {
                    store.open(.calendar(.day, date: next.start))
                }
            }
        }
        .lineLimit(1)
    }

    private var focusLabel: String {
        if store.focus.mode == .break { return "On break" }
        return store.focus.isPaused ? "Focus paused" : "Focus running"
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "MATH 26103 · Discrete Math" → "Discrete Math".
    static func shortTitle(_ title: String) -> String {
        title.components(separatedBy: " · ").last ?? title
    }
}
