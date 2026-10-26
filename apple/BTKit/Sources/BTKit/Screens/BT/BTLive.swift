import SwiftUI

/// The BT screen on the real server: `AppStore.chat` supplies the conversations, streamed
/// replies and tool approvals. Ledger and memories stay local until the server sends them.
enum BTLive {
    static let streamingID = "streaming"

    /// Server turns as BT messages, with the reply streaming so far last.
    static func messages(turns: [ChatTurn], streaming: String?, now: Date) -> [Message] {
        let saved = turns.map {
            Message(id: $0.id, role: $0.role == "user" ? .user : .bt, text: $0.text,
                    time: Date(timeIntervalSince1970: $0.ts), isCloud: $0.compute == "openai")
        }
        guard let streaming else { return saved }
        return saved + [Message(id: streamingID, role: .bt, text: streaming.isEmpty ? "…" : streaming, time: now)]
    }

    /// The server's memory index as "BT remembers" rows, tagged by memory type.
    static func memories(_ server: [ServerMemory]) -> [Memory] {
        let iso = ISO8601DateFormatter()
        return server.map {
            Memory(id: $0.name, text: $0.description, tag: $0.type.uppercased(), createdAt: iso.date(from: $0.updated) ?? .distantPast)
        }
    }
}

extension AppStore {
    /// True when BT talks to a server instead of the sample responder.
    var btIsLive: Bool { chat?.endpoints != nil }

    /// Server memories when live, else the sample ones.
    var shownMemories: [Memory] {
        guard let chat, btIsLive else { return memories }
        return BTLive.memories(chat.memories)
    }
}

extension BTFormat {
    /// Thread row meta: "NOW", "2H", "TUE"; "NEW" when nothing was said yet.
    static func age(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "NEW" }
        guard calendar.isDate(date, inSameDayAs: now) else { return weekday(date, calendar).uppercased() }
        let hours = Int(now.timeIntervalSince(date) / 3600)
        return hours < 1 ? "NOW" : "\(hours)H"
    }
}

/// A tool call waiting for the owner, as a paper card with Deny / Approve.
struct BTApprovalCard: View {
    let approval: ToolApproval
    let chat: ChatModel

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("BT wants to run \(approval.toolName)").monoLabel(10, color: .btAccentText)
                Text(approval.summary).font(.inter(15, .semibold))
                ForEach(approval.arguments, id: \.self) { line in
                    Text(line).font(.mono(11)).foregroundStyle(Color.btMuted).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button("Approve") { Task { await chat.approve(approval.id) } }.buttonStyle(.pill(.primary))
                    Button("Deny") { Task { await chat.deny(approval.id) } }.buttonStyle(.pill(.secondary))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}

/// The server's error with a Retry link.
struct BTErrorRow: View {
    let message: String
    let chat: ChatModel

    var body: some View {
        HStack(spacing: 12) {
            Text(message).font(.mono(11)).foregroundStyle(Color.btAccentText)
            Spacer()
            Button("Retry") { Task { await chat.retry() } }.buttonStyle(.monoLink).frame(minHeight: 44)
        }
    }
}

/// Shown over the sample threads while no server address is set.
struct BTOfflineNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sample data").monoLabel(10, color: .btAccentText)
            Text("Set your BT server address in Settings to talk to BT.").font(.inter(13)).foregroundStyle(Color.btMuted)
            SettingsLink { Text("Open Settings →") }.buttonStyle(.monoLink).frame(minHeight: 44)
        }
    }
}

/// Keeps `chat.serverAddress` in step with the address saved in Settings.
struct BTServerAddressSync: ViewModifier {
    let chat: ChatModel?
    @AppStorage("serverAddress") private var serverAddress = ""

    func body(content: Content) -> some View {
        content.task(id: serverAddress) {
            guard let chat else { return }
            if chat.serverAddress == serverAddress {
                await chat.loadSessions()
                return
            }
            // Settings edits arrive per keystroke; wait until typing pauses.
            if !chat.serverAddress.isEmpty {
                guard (try? await Task.sleep(for: .milliseconds(700))) != nil else { return }
            }
            chat.serverAddress = serverAddress
        }
    }
}
