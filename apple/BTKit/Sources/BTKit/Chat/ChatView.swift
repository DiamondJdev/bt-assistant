import SwiftUI

/// Conversation list beside the selected conversation.
struct ChatView: View {
    @Bindable var model: ChatModel
    @AppStorage("serverAddress") private var serverAddress = ""

    var body: some View {
        Group {
            if model.endpoints == nil {
                setup
            } else {
                HStack(spacing: 0) {
                    conversationList.frame(width: 220)
                    Divider()
                    conversation
                }
            }
        }
        .task(id: serverAddress) {
            if model.serverAddress == serverAddress {
                await model.loadSessions()
                return
            }
            // Settings edits arrive per keystroke; wait until typing pauses.
            if !model.serverAddress.isEmpty {
                guard (try? await Task.sleep(for: .milliseconds(700))) != nil else { return }
            }
            model.serverAddress = serverAddress
        }
    }

    private var setup: some View {
        ContentUnavailableView {
            Label("No BT server", systemImage: "network.slash")
        } description: {
            Text("Set your BT server address in Settings.")
        } actions: {
            #if os(macOS)
            SettingsLink { Text("Open Settings") }
            #endif
        }
        .accessibilityIdentifier("bt-setup")
    }

    private var conversationList: some View {
        let selection = Binding(
            get: { model.selectedSessionID },
            set: { id in Task { await model.select(id) } }
        )
        return List(model.sessions, selection: selection) { session in
            Text(session.label).lineLimit(2).tag(session.id)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("New Conversation", systemImage: "square.and.pencil") { model.startNewConversation() }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadSessions() } }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.turns) { turn in
                            TurnBubble(text: turn.text, isUser: turn.role == "user", isCloud: turn.compute == "openai")
                        }
                        if let streaming = model.streamingText {
                            TurnBubble(text: streaming.isEmpty ? "…" : streaming, isUser: false, isCloud: false)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: model.turns.count) { proxy.scrollTo("bottom") }
                .onChange(of: model.streamingText) { proxy.scrollTo("bottom") }
            }
            if let error = model.errorMessage {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { Task { await model.retry() } }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                TextField("Message BT", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .onSubmit { Task { await model.send() } }
                Button("Send", systemImage: "arrow.up.circle.fill") { Task { await model.send() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
    }
}

private struct TurnBubble: View {
    let text: String
    let isUser: Bool
    let isCloud: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(rendered).textSelection(.enabled)
                if isCloud {
                    Text("Cloud").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
