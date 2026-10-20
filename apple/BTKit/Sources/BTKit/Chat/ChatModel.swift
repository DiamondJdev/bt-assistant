import Foundation
import Observation

/// Conversation list, history and one streaming socket for the BT pane.
/// The socket opens on the first send and reopens on the next send after it drops.
@MainActor
@Observable
public final class ChatModel {
    static let declinedToolResult = "This app does not run tools yet."
    static let lostConnection = "Lost connection to BT. Try again."
    static let sendFailed = "Couldn't reach BT. Check the server address and try again."

    /// Setting a new address resets state and reloads the list.
    public var serverAddress = "" {
        didSet {
            guard serverAddress != oldValue else { return }
            reset()
            sessions = []
            Task { await loadSessions() }
        }
    }

    public var endpoints: ChatEndpoints? { ChatEndpoints(serverAddress: serverAddress) }

    public private(set) var sessions: [ChatSessionSummary] = []
    public var selectedSessionID: String?
    public private(set) var turns: [ChatTurn] = []
    public var draft = ""
    /// Non-nil while a reply is in flight; holds the text streamed so far.
    public private(set) var streamingText: String?
    public private(set) var errorMessage: String?
    public var isSending: Bool { streamingText != nil }

    private let makeAPI: (ChatEndpoints) -> any ChatAPI
    private let makeSocket: (URL) -> any ChatSocket
    private var socket: (any ChatSocket)?

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
            sessions = try await makeAPI(endpoints).sessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ id: String?) async {
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
            try await connectedSocket(endpoints).send(.message(text: text, context: nil))
        } catch {
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
        Task { await receiveLoop(socket) }
        try await socket.send(.hello(tools: []))
        return socket
    }

    private func receiveLoop(_ socket: any ChatSocket) async {
        while true {
            let frame: ServerFrame
            do {
                frame = try await socket.receive()
            } catch {
                guard self.socket === socket else { return }
                self.socket = nil
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
            if isSending { streamingText? += text }
        case .toolCall(let id, _):
            try? await socket.send(.toolResult(id: id, ok: false, content: Self.declinedToolResult))
        case .done(let text, let compute, _):
            turns.append(ChatTurn(id: UUID().uuidString, ts: Date().timeIntervalSince1970, role: "bt", text: text, compute: compute))
            streamingText = nil
            await loadSessions()
        case .error(let message):
            errorMessage = message
            streamingText = nil
            // A rejected message may not have been saved; the server's history is the truth.
            if let id = selectedSessionID, let endpoints,
               let history = try? await makeAPI(endpoints).history(sessionID: id),
               selectedSessionID == id {
                turns = history
            }
        case .unknown:
            break
        }
    }

    private func dropSocket() {
        socket?.close()
        socket = nil
    }

    private func reset() {
        dropSocket()
        turns = []
        streamingText = nil
        errorMessage = nil
    }
}
