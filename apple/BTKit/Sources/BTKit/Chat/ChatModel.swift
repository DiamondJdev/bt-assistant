import Foundation
import Observation

/// A tool call waiting for the owner, shown as a card in the chat pane.
public struct ToolApproval: Identifiable, Equatable {
    /// The server's call id.
    public let id: String
    public let toolName: String
    /// The tool's description, which names it in plain words.
    public let summary: String
    /// Sorted `key: value` lines.
    public let arguments: [String]
}

/// Conversation list, history and one streaming socket for the BT pane.
/// The socket opens on the first send and reopens on the next send after it drops.
@MainActor
@Observable
public final class ChatModel {
    static let lostConnection = "Lost connection to BT. Try again."
    static let sendFailed = "Couldn't reach BT. Check the server address and try again."

    /// Setting a new address resets state and reloads the list.
    public var serverAddress = "" {
        didSet {
            guard serverAddress != oldValue else { return }
            reset()
            // Session ids belong to the old server.
            selectedSessionID = nil
            sessions = []
            memories = []
            Task { await loadSessions() }
        }
    }

    public var endpoints: ChatEndpoints? { ChatEndpoints(serverAddress: serverAddress) }

    public private(set) var sessions: [ChatSessionSummary] = []
    /// The server's memory index, for "BT remembers".
    public private(set) var memories: [ServerMemory] = []
    public var selectedSessionID: String?
    public private(set) var turns: [ChatTurn] = []
    public var draft = ""
    /// Non-nil while a reply is in flight; holds the text streamed so far.
    public private(set) var streamingText: String?
    public private(set) var errorMessage: String?
    public var isSending: Bool { streamingText != nil }
    /// Modules whose tools are offered in `hello` and whose snapshots, in this order, become each
    /// message's context. Set by the app once the sidebar exists.
    public var modules: [any ToolModule] = []
    public private(set) var pendingApprovals: [ToolApproval] = []

    private let makeAPI: (ChatEndpoints) -> any ChatAPI
    private let makeSocket: (URL) -> any ChatSocket
    private var socket: (any ChatSocket)?
    #if BT_DIAGNOSTICS
    private var diagnosticsRequested = false
    private var diagnosticTurnID: String?
    private var approvalStarts: [String: Double] = [:]

    public func enableDiagnostics() {
        diagnosticsRequested = true
    }
    #endif
    /// What each pending approval needs to run once the owner answers.
    private var waitingCalls: [String: WaitingCall] = [:]

    public init(
        makeAPI: @escaping (ChatEndpoints) -> any ChatAPI = URLSessionChatAPI.init,
        makeSocket: @escaping (URL) -> any ChatSocket = URLSessionChatSocket.init
    ) {
        self.makeAPI = makeAPI
        self.makeSocket = makeSocket
    }

    public func loadSessions() async {
        guard let endpoints else { return }
        do {
            let api = makeAPI(endpoints)
            sessions = try await api.sessions()
            errorMessage = nil
            // A server older than /memories answers 404; keep the list empty rather than show an error.
            memories = (try? await api.memories()) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ id: String?) async {
        #if BT_DIAGNOSTICS
        let historyStart = ProcessInfo.processInfo.systemUptime
        defer { DiagnosticsRecorder.shared.sample(.history, milliseconds: (ProcessInfo.processInfo.systemUptime - historyStart) * 1000) }
        #endif
        reset()
        selectedSessionID = id
        guard let id, let endpoints else { return }
        do {
            let history = try await makeAPI(endpoints).history(sessionID: id)
            // Ignore history that arrives after the owner picked another conversation.
            if selectedSessionID == id { turns = history }
        } catch {
            if selectedSessionID == id { errorMessage = error.localizedDescription }
        }
    }

    /// Reloads the list, and the selected conversation if its history never loaded.
    public func retry() async {
        await loadSessions()
        if errorMessage == nil, turns.isEmpty, let id = selectedSessionID {
            await select(id)
        }
    }

    public func startNewConversation() {
        reset()
        selectedSessionID = nil
    }

    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, let endpoints else { return }
        let local = ChatTurn(id: UUID().uuidString, ts: Date().timeIntervalSince1970, role: "user", text: text, compute: nil)
        turns.append(local)
        draft = ""
        errorMessage = nil
        streamingText = ""
        do {
            let fragments = modules.map(\.snapshot)
            let context = contextSnapshot(fragments)
            var message = ClientFrame.message(text: text, context: context)
            #if BT_DIAGNOSTICS
            if diagnosticsRequested, DiagnosticsRecorder.shared.enabled {
                let turnID = UUID().uuidString
                diagnosticTurnID = turnID
                DiagnosticsRecorder.shared.begin(
                    turnID: turnID, contextChars: context?.unicodeScalars.count ?? 0,
                    omittedSnapshots: omittedSnapshotCount(fragments)
                )
                message = .message(text: text, context: context, turnID: turnID, diagnostics: true)
            }
            #endif
            try await connectedSocket(endpoints).send(message)
        } catch {
            #if BT_DIAGNOSTICS
            finishDiagnosticTurn(.failed)
            #endif
            dropSocket()
            turns.removeAll { $0.id == local.id }
            draft = text
            streamingText = nil
            errorMessage = Self.sendFailed
        }
    }

    private func connectedSocket(_ endpoints: ChatEndpoints) async throws -> any ChatSocket {
        if let socket { return socket }
        let socket = makeSocket(endpoints.socketURL(sessionID: selectedSessionID))
        self.socket = socket
        #if BT_DIAGNOSTICS
        if let diagnosticTurnID { DiagnosticsRecorder.shared.event(.connected, turnID: diagnosticTurnID) }
        #endif
        Task { await receiveLoop(socket) }
        // The server keeps tools per connection, so every new socket offers them first.
        try await socket.send(.hello(tools: modules.flatMap(\.tools)))
        return socket
    }

    /// Runs a waiting call and sends its result. Does nothing once the card is gone.
    public func approve(_ id: String) async {
        guard let call = takeWaitingCall(id) else { return }
        await run(call.module, call.name, call.args, id: id, socket: call.socket)
    }

    /// Tells the server the owner declined a waiting call. Does nothing once the card is gone.
    public func deny(_ id: String) async {
        guard let call = takeWaitingCall(id) else { return }
        await reply(.toolResult(id: id, ok: false, content: "The owner declined this action."), on: call.socket)
    }

    private func takeWaitingCall(_ id: String) -> WaitingCall? {
        #if BT_DIAGNOSTICS
        if let started = approvalStarts.removeValue(forKey: id) {
            DiagnosticsRecorder.shared.sample(.approvalWait, milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000)
            if let diagnosticTurnID { DiagnosticsRecorder.shared.event(.approvalResolved, turnID: diagnosticTurnID) }
        }
        #endif
        pendingApprovals.removeAll { $0.id == id }
        return waitingCalls.removeValue(forKey: id)
    }

    private func handleToolCall(id: String, name: String, args: JSONValue, from socket: any ChatSocket) async {
        guard let module = modules.first(where: { $0.tools.contains { $0.name == name } }),
              let tool = module.tools.first(where: { $0.name == name })
        else {
            await reply(.toolResult(id: id, ok: false, content: ToolError.unknownTool(name).localizedDescription), on: socket)
            return
        }
        guard tool.needsApproval else {
            await run(module, name, args, id: id, socket: socket)
            return
        }
        waitingCalls[id] = WaitingCall(module: module, name: name, args: args, socket: socket)
        #if BT_DIAGNOSTICS
        if let diagnosticTurnID {
            approvalStarts[id] = ProcessInfo.processInfo.systemUptime
            DiagnosticsRecorder.shared.event(.approvalRequested, turnID: diagnosticTurnID)
        }
        #endif
        pendingApprovals.append(ToolApproval(id: id, toolName: name, summary: tool.description, arguments: argumentLines(args)))
    }

    private func run(_ module: any ToolModule, _ name: String, _ args: JSONValue, id: String, socket: any ChatSocket) async {
        #if BT_DIAGNOSTICS
        let started = ProcessInfo.processInfo.systemUptime
        let turnID = diagnosticTurnID
        if let turnID { DiagnosticsRecorder.shared.event(.toolStarted, turnID: turnID) }
        defer {
            if let turnID {
                DiagnosticsRecorder.shared.sample(.toolExecution, milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000)
                DiagnosticsRecorder.shared.event(.toolFinished, turnID: turnID)
            }
        }
        #endif
        let result: ClientFrame
        do {
            let prose = try await module.call(name, arguments: JSONEncoder().encode(args))
            result = .toolResult(id: id, ok: true, content: prose)
        } catch {
            result = .toolResult(id: id, ok: false, content: error.localizedDescription)
        }
        await reply(result, on: socket)
    }

    /// Sends on the socket the call came from; a result for a dropped socket has nowhere to go.
    private func reply(_ frame: ClientFrame, on socket: any ChatSocket) async {
        guard self.socket === socket else { return }
        // A failed write means the socket is going; the receive loop reports the lost connection.
        try? await socket.send(frame)
    }

    private func clearApprovals() {
        #if BT_DIAGNOSTICS
        approvalStarts.removeAll()
        #endif
        pendingApprovals = []
        waitingCalls = [:]
    }

    private func receiveLoop(_ socket: any ChatSocket) async {
        while true {
            let frame: ServerFrame
            do {
                frame = try await socket.receive()
            } catch {
                guard self.socket === socket else { return }
                self.socket = nil
                #if BT_DIAGNOSTICS
                finishDiagnosticTurn(.disconnected)
                #endif
                clearApprovals()
                if isSending {
                    streamingText = nil
                    errorMessage = Self.lostConnection
                }
                return
            }
            guard self.socket === socket else { return }
            await handle(frame, from: socket)
        }
    }

    private func handle(_ frame: ServerFrame, from socket: any ChatSocket) async {
        switch frame {
        case .session(let id):
            if selectedSessionID == nil { selectedSessionID = id }
        case .delta(let text):
            #if BT_DIAGNOSTICS
            if isSending, !text.isEmpty, let diagnosticTurnID { DiagnosticsRecorder.shared.event(.firstText, turnID: diagnosticTurnID) }
            #endif
            BTPerformance.measure(.frameHandling) {
                if isSending { streamingText? += text }
            }
        case .done(let text, let compute, _, let turnID, let metrics):
            #if BT_DIAGNOSTICS
            if let diagnosticTurnID {
                if let metrics, turnID == diagnosticTurnID { DiagnosticsRecorder.shared.update(turnID: diagnosticTurnID, metrics: metrics) }
                // A reply that arrives whole (cloud fallback) shows its first text here.
                if streamingText?.isEmpty ?? true, !text.isEmpty {
                    DiagnosticsRecorder.shared.event(.firstText, turnID: diagnosticTurnID)
                }
            }
            finishDiagnosticTurn(.completed)
            #endif
            turns.append(ChatTurn(id: UUID().uuidString, ts: Date().timeIntervalSince1970, role: "bt", text: text, compute: compute))
            streamingText = nil
            // The server stopped waiting; a late answer would go nowhere.
            clearApprovals()
            await loadSessions()
        case .error(let message):
            #if BT_DIAGNOSTICS
            finishDiagnosticTurn(.failed)
            #endif
            errorMessage = message
            streamingText = nil
            clearApprovals()
            // A rejected message may not have been saved; the server's history is the truth.
            if let id = selectedSessionID, let endpoints,
               let history = try? await makeAPI(endpoints).history(sessionID: id),
               selectedSessionID == id {
                turns = history
            }
        case .toolCall(let id, let name, let args):
            await handleToolCall(id: id, name: name, args: args, from: socket)
        case .unknown:
            break
        case .metrics(let turnID, let metrics):
            #if BT_DIAGNOSTICS
            if turnID == diagnosticTurnID { DiagnosticsRecorder.shared.update(turnID: turnID, metrics: metrics) }
            #endif
        }
    }

    private func dropSocket() {
        socket?.close()
        socket = nil
    }

    private func reset() {
        #if BT_DIAGNOSTICS
        finishDiagnosticTurn(.cancelled)
        #endif
        dropSocket()
        clearApprovals()
        turns = []
        streamingText = nil
        errorMessage = nil
    }

    #if BT_DIAGNOSTICS
    private func finishDiagnosticTurn(_ status: DiagnosticTurnStatus) {
        guard let diagnosticTurnID else { return }
        DiagnosticsRecorder.shared.finish(turnID: diagnosticTurnID, status: status)
        self.diagnosticTurnID = nil
    }
    #endif
}

private struct WaitingCall {
    let module: any ToolModule
    let name: String
    let args: JSONValue
    let socket: any ChatSocket
}

/// Sorted `key: value` lines for an approval card; strings print bare, anything else as JSON.
private func argumentLines(_ args: JSONValue) -> [String] {
    guard case .object(let fields) = args else { return [] }
    return fields.keys.sorted().map { key in
        let value: String
        if case .string(let text) = fields[key] {
            value = text
        } else {
            value = (try? JSONEncoder().encode(fields[key])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        return "\(key): \(value)"
    }
}
