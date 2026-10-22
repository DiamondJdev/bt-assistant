import SwiftUI

/// Columns 2–3: the selected thread's messages over the composer.
struct BTConversation: View {
    @Bindable var store: AppStore

    private var thread: ChatThread? { store.thread(store.selectedThreadID) }

    var body: some View {
        VStack(spacing: 0) {
            messages
            BTComposer(store: store)
                .dashedEdges(right: false, bottom: false, top: true)
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView { messageList }
                .defaultScrollAnchor(.bottom)
            .onChange(of: thread?.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    var messageList: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let thread, thread.messages.isEmpty { emptyState(thread) }
            ForEach(thread?.messages ?? []) { message in
                BTMessageView(store: store, message: message).id(message.id)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ thread: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = store.project(thread.projectID)?.name {
                Text("Scoped to \(name)").monoLabel(color: .btAccentText)
            }
            Text(thread.title).interStyle(40, .medium, tracking: -0.045)
            Text("Start with a shortcut below, or just say what you need.").foregroundStyle(Color.btMuted)
        }
        .padding(.vertical, 40)
    }
}

/// One message: a right-aligned ink bubble for the user, or BT's label, text, insight and cards.
struct BTMessageView: View {
    let store: AppStore
    let message: Message

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 100)
                Text(message.text ?? "")
                    .font(.inter(17))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.btInkOnDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.btInk)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("BT · \(BTFormat.clockWithPeriod(message.time, store.calendar))").monoLabel()
                if let text = message.text {
                    Text(text).font(.inter(17)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }
                if let insight = message.insight { BTInsightCard(insight: insight, open: store.open) }
                if !message.resultCards.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 2), alignment: .leading, spacing: 8) {
                        ForEach(message.resultCards) { BTResultCardView($0, open: store.open) }
                    }
                }
            }
            .padding(.trailing, 60)
        }
    }
}

/// Big number, a sentence and a deep link, in a dashed box.
struct BTInsightCard: View {
    let insight: Insight
    let open: (DeepLink) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(insight.value).interStyle(44, .medium, tracking: -0.05).fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.sentence).font(.inter(15)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                if let link = insight.link {
                    Button(Self.label(link)) { open(link) }.buttonStyle(.monoLink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Rectangle().strokeBorder(Color.btSubtle, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
    }

    static func label(_ link: DeepLink) -> String {
        switch link {
        case .code: "Open in Code →"
        case .calendar: "Open in Calendar →"
        case .focus: "Open Focus →"
        case .today: "Open Today →"
        case .bt: "Open thread →"
        }
    }
}

/// Shortcut chips and the "Tell BT…" field. Enter sends.
struct BTComposer: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool

    static let chips = ["/block", "/remember", "/todo", "/status", "@code"]

    var body: some View {
        @Bindable var state = store.btScreen
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Self.chips, id: \.self) { chip in
                    Button {
                        store.btScreen.draft = chip + " "
                        focused = true
                    } label: {
                        Text(chip).font(.mono(11)).padding(.horizontal, 10).frame(height: 28)
                            .overlay(Rectangle().strokeBorder(Color.btLine, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert \(chip)")
                }
            }
            HStack(spacing: 10) {
                TextField("Tell BT… try “/remember the lab is in room 210”", text: $state.draft)
                    .textFieldStyle(.plain)
                    .interStyle(24, tracking: -0.02)
                    .focused($focused)
                    .onSubmit(send)
                    .accessibilityLabel("Message BT")
                Button(action: send) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.btInkOnDark)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.btInk))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func send() {
        let text = store.btScreen.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.btScreen.draft = ""
        store.selectedThreadID = store.sendToBT(text, threadID: store.selectedThreadID)
    }
}
