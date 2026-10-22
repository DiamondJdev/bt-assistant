import SwiftUI

/// Column 1: New thread, the thread list and "BT remembers".
struct BTThreadsColumn: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView { content }.scrollIndicators(.never)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            newThreadButton
            threadList
            BTMemoryList(store: store)
        }
        .padding(BTMetrics.cellPadding)
    }

    private var newThreadButton: some View {
        Button { store.newBTThread() } label: {
            HStack {
                Text("New thread").font(.inter(13))
                Spacer()
                Text("⌘N").font(.mono(11)).foregroundStyle(Color.btMuted)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .overlay(Capsule().strokeBorder(Color.btInk, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("New thread")
    }

    private var threadList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Threads").monoLabel().padding(.bottom, 8)
            ForEach(store.threads) { thread in
                BTThreadRow(store: store, thread: thread)
            }
        }
    }
}

private struct BTThreadRow: View {
    let store: AppStore
    let thread: ChatThread

    private var selected: Bool { store.selectedThreadID == thread.id }

    var body: some View {
        Button { store.selectedThreadID = thread.id } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(.inter(14, selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let name = store.project(thread.projectID)?.name {
                        Text("Project · \(name)").monoLabel(10, color: .btAccentText)
                    }
                }
                Spacer(minLength: 8)
                Text(meta).font(.mono(11)).foregroundStyle(selected ? Color.btAccentText : Color.btMuted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .overlay(alignment: .top) { Rectangle().fill(Color.btRule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "NOW", "2H", "TUE" from the latest message; "NEW" when empty.
    private var meta: String {
        guard let last = thread.messages.last?.time else { return "NEW" }
        let cal = store.calendar
        guard cal.isDate(last, inSameDayAs: store.now) else { return BTFormat.weekday(last, cal).uppercased() }
        let hours = Int(store.now.timeIntervalSince(last) / 3600)
        return hours < 1 ? "NOW" : "\(hours)H"
    }
}

/// "BT remembers": newest first, the newest one highlighted.
struct BTMemoryList: View {
    @Bindable var store: AppStore

    private var sorted: [Memory] { store.memories.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        let all = sorted
        let shown = store.btScreen.showAllMemories ? all : Array(all.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BT remembers")
                Spacer()
                Text("\(all.count)")
            }
            .monoLabel()
            ForEach(shown) { memory in
                row(memory, isNew: memory.id == all.first?.id)
            }
            if all.count > 3 {
                Button(store.btScreen.showAllMemories ? "Show fewer" : "See all →") {
                    store.btScreen.showAllMemories.toggle()
                }
                .buttonStyle(.monoLink)
                .underline()
                .frame(minHeight: 44)
            }
        }
    }

    private func row(_ memory: Memory, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.text).font(.inter(14, isNew ? .medium : .regular))
            Text((isNew ? "New · " : "") + memory.tag).monoLabel(10, tracking: 0, color: isNew ? .btAccentDeep : .btMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isNew ? Color.btPaper : .clear)
        .overlay(Rectangle().strokeBorder(isNew ? Color.btAccent : Color.btTrack, lineWidth: isNew ? 1.5 : 1))
    }
}
