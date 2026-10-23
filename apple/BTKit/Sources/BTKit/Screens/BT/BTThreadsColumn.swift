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
            if store.chat != nil, !store.btIsLive { BTOfflineNotice() }
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

    @ViewBuilder private var threadList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Threads").monoLabel().padding(.bottom, 8)
            if let chat = store.chat, store.btIsLive {
                ForEach(chat.sessions) { session in
                    BTThreadRow(
                        title: session.label, project: nil,
                        meta: BTFormat.age(Date(timeIntervalSince1970: session.updatedAt), now: store.now, calendar: store.calendar),
                        selected: chat.selectedSessionID == session.id
                    ) { Task { await chat.select(session.id) } }
                }
            } else {
                ForEach(store.threads) { thread in
                    BTThreadRow(
                        title: thread.title, project: store.project(thread.projectID)?.name,
                        meta: BTFormat.age(thread.messages.last?.time, now: store.now, calendar: store.calendar),
                        selected: store.selectedThreadID == thread.id
                    ) { store.selectedThreadID = thread.id }
                }
            }
        }
    }
}

private struct BTThreadRow: View {
    let title: String
    let project: String?
    let meta: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.inter(14, selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let project {
                        Text("Project · \(project)").monoLabel(10, color: .btAccentText)
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
