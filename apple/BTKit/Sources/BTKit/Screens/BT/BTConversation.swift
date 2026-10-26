import SwiftUI

/// Columns 2–3: the selected thread's messages over the composer.
struct BTConversation: View {
    @Bindable var store: AppStore

    private var thread: ChatThread? { store.thread(store.selectedThreadID) }

    /// Server turns when live, else the selected sample thread.
    private var shown: [Message] {
        guard let chat = store.chat, store.btIsLive else { return thread?.messages ?? [] }
        return BTPerformance.measure(.messageTransform) {
            BTLive.messages(turns: chat.turns, streaming: chat.streamingText, now: store.now)
        }
    }

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
            // Text too, so a streaming reply keeps the bottom in view.
            .onChange(of: [shown.last?.id, shown.last?.text, store.chat?.pendingApprovals.last?.id]) {
                BTPerformance.measure(.scroll) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    var messageList: some View {
        VStack(alignment: .leading, spacing: 22) {
            let messages = shown
            if messages.isEmpty { emptyState }
            ForEach(messages) { message in
                BTMessageView(store: store, message: message)
            }
            if let chat = store.chat, store.btIsLive {
                ForEach(chat.pendingApprovals) { BTApprovalCard(approval: $0, chat: chat) }
                if let error = chat.errorMessage { BTErrorRow(message: error, chat: chat) }
            }
            Color.clear.frame(height: 1).id("bottom")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        let live = store.btIsLive
        return VStack(alignment: .leading, spacing: 8) {
            if !live, let name = store.project(thread?.projectID)?.name {
                Text("Scoped to \(name)").monoLabel(color: .btAccentText)
            }
            Text(live ? "New conversation" : thread?.title ?? "New thread").interStyle(40, .medium, tracking: -0.045)
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
                Text("BT · \(BTFormat.clockWithPeriod(message.time, store.calendar))" + (message.provider.map { " · \($0)" } ?? ""))
                    .monoLabel()
                if let text = message.text {
                    Text(Self.markdown(text)).textSelection(.enabled).font(.inter(17)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
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

    /// Inline markdown (bold, code, links) from the server; plain text when it doesn't parse.
    static func markdown(_ text: String) -> AttributedString {
        BTPerformance.measure(.markdown) {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
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
        let draft = store.chat.flatMap { chat in store.btIsLive ? Bindable(chat).draft : nil } ?? $state.draft
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Self.chips, id: \.self) { chip in
                    Button {
                        draft.wrappedValue = chip + " "
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
                TextField("Tell BT… try “/remember the lab is in room 210”", text: draft)
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
                .disabled(store.chat?.isSending == true && store.btIsLive)
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
        if let chat = store.chat, store.btIsLive {
            Task { await chat.send() }
            return
        }
        let text = store.btScreen.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.btScreen.draft = ""
        store.selectedThreadID = store.sendToBT(text, threadID: store.selectedThreadID)
    }
}
