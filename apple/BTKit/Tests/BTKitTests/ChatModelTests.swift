import Foundation
import SwiftUI
import Testing
@testable import BTKit

@MainActor
struct ChatModelTests {
    private let api = FakeChatAPI()
    private let factory = FakeSocketFactory()

    private func makeModel() -> ChatModel {
        let api = api
        let factory = factory
        let model = ChatModel(makeAPI: { _ in api }, makeSocket: { factory.make($0) })
        model.serverAddress = "https://bt.example.ts.net"
        return model
    }

    private func sendHi(_ model: ChatModel) async -> FakeChatSocket {
        model.draft = "Hi"
        await model.send()
        return factory.made.last!
    }

    @Test func deltasAccumulateAndDoneReplacesThem() async throws {
        let model = makeModel()
        let socket = await sendHi(model)
        #expect(model.isSending && model.streamingText == "")

        socket.push(.delta("Hel"))
        socket.push(.delta("lo"))
        try await waitUntil { model.streamingText == "Hello" }
        socket.push(.done(text: "Hello!", compute: "ollama", toolsUsed: []))
        try await waitUntil { model.streamingText == nil }

        #expect(model.turns.map(\.role) == ["user", "bt"])
        #expect(model.turns.last?.text == "Hello!")
        #expect(model.turns.last?.compute == "ollama")
        try await waitUntil { model.sessions == api.summaries }
    }

    @Test func newConversationAdoptsTheServerSessionID() async throws {
        let model = makeModel()
        model.startNewConversation()
        let socket = await sendHi(model)
        #expect(factory.urls == [URL(string: "wss://bt.example.ts.net/chat/ws")!])

        socket.push(.session(id: "s9"))
        try await waitUntil { model.selectedSessionID == "s9" }
    }

    @Test func selectingLoadsHistoryAndSendsOnThatSession() async {
        let model = makeModel()
        await model.select("s1")
        #expect(model.turns == api.turns)

        _ = await sendHi(model)
        #expect(factory.urls == [URL(string: "wss://bt.example.ts.net/chat/ws?session_id=s1")!])
    }

    @Test func firstSendSendsHelloThenTheMessage() async {
        let model = makeModel()
        let socket = await sendHi(model)
        #expect(socket.sent == [.hello(tools: []), .message(text: "Hi", context: nil)])
        #expect(model.draft.isEmpty)
    }

    @Test func helloOffersEveryModuleToolAndMessageCarriesTheSnapshot() async {
        let model = makeModel()
        let tools = FakeToolModule(snapshot: "Tools ready")
        model.modules = [BTModule(), tools, FakeToolModule(id: "quiet", snapshot: nil)]
        let socket = await sendHi(model)
        #expect(socket.sent.first == .hello(tools: tools.tools + FakeToolModule(id: "quiet").tools))
        #expect(socket.sent.last == .message(text: "Hi", context: "Tools ready"))
    }

    #if BT_DIAGNOSTICS
    @Test func diagnosticTurnIsTaggedTimedAndMatchedToItsMetrics() async throws {
        let model = makeModel()
        model.enableDiagnostics()
        let socket = await sendHi(model)
        guard case .message(_, _, let turnID?, true) = socket.sent.last else {
            Issue.record("Expected a diagnostic message, got \(String(describing: socket.sent.last))")
            return
        }
        #expect(turnID == turnID.lowercased())
        socket.push(.metrics(turnID: turnID.lowercased(), metrics: ServerMetrics(durationMs: 21)))
        try await waitUntil { DiagnosticsRecorder.shared.snapshot().turns.first { $0.id == turnID }?.server?.durationMs == 21 }
        socket.push(.metrics(turnID: "someone-else", metrics: ServerMetrics(durationMs: 1)))
        socket.push(.delta("Hel"))
        socket.push(.delta("lo"))
        socket.push(.done(text: "Hello", compute: "ollama", toolsUsed: [], turnID: turnID.lowercased(), metrics: ServerMetrics(durationMs: 42)))
        try await waitUntil { model.streamingText == nil }

        let turn = try #require(DiagnosticsRecorder.shared.snapshot().turns.first { $0.id == turnID })
        #expect(turn.status == .completed)
        #expect(turn.chunks == 2)
        #expect(turn.firstTextMs != nil)
        #expect(turn.server?.durationMs == 42)
    }

    @Test(arguments: [true, false])
    func failedDiagnosticTurnRetainsOnlyMatchingServerMetrics(matches: Bool) async throws {
        let model = makeModel()
        model.enableDiagnostics()
        let socket = await sendHi(model)
        guard case .message(_, _, let turnID?, true) = socket.sent.last else {
            Issue.record("Expected diagnostic turn")
            return
        }
        let serverTurnID = matches ? turnID : "another-turn"
        let json = """
        {"type":"error","message":"Response failed.","turn_id":"\(serverTurnID)","metrics":{"duration_ms":73}}
        """
        socket.push(try ChatJSON.decoder.decode(ServerFrame.self, from: Data(json.utf8)))
        try await waitUntil { !model.isSending }
        let turn = try #require(DiagnosticsRecorder.shared.snapshot().turns.first { $0.id == turnID })
        #expect(turn.status == .failed)
        #expect(turn.server?.durationMs == (matches ? 73 : nil))
    }
    #endif

    @Test func plainModelSendsNoDiagnostics() async {
        let socket = await sendHi(makeModel())
        #expect(socket.sent.last == .message(text: "Hi", context: nil))
    }

    @Test func nonApprovalCallRunsAndRepliesOK() async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_read", args: ["q": "x"]))
        try await waitUntil { socket.sent.count == 3 }
        #expect(socket.sent.last == .toolResult(id: "c1", ok: true, content: "read {\"q\":\"x\"}"))
        #expect(model.pendingApprovals.isEmpty)
    }

    @Test func approvalCallWaitsThenApproveReplies() async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_write", args: ["title": "Lab", "n": 2]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        #expect(model.pendingApprovals == [
            ToolApproval(id: "c1", toolName: "fake_write", summary: "Write a thing.", arguments: ["n: 2", "title: Lab"]),
        ])
        #expect(socket.sent.count == 2)

        await model.approve("c1")
        #expect(model.pendingApprovals.isEmpty)
        #expect(module.calls.isEmpty)
        #expect(socket.sent.last == .toolApproval(id: "c1"))
        let acknowledgement = try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"tool_approved","id":"c1"}"#.utf8))
        socket.push(acknowledgement)
        try await waitUntil { socket.sent.count == 4 }
        #expect(socket.sent.last == .toolResult(id: "c1", ok: true, content: "wrote"))
        socket.push(acknowledgement)
        socket.push(.delta("Done"))
        try await waitUntil { model.streamingText == "Done" }
        #expect(module.calls == ["fake_write"])
    }

    @Test(arguments: [true, false])
    func cancelledApprovalCannotRunBeforeTheTurnFinishes(approvalRequested: Bool) async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_write", args: [:]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        if approvalRequested { await model.approve("c1") }
        #expect(module.calls.isEmpty)
        socket.push(try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"tool_cancelled","id":"c1"}"#.utf8)))
        socket.push(try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"tool_approved","id":"c1"}"#.utf8)))
        socket.push(.delta("Still responding"))
        try await waitUntil { model.streamingText == "Still responding" }
        await model.approve("c1")
        #expect(module.calls.isEmpty)
        #expect(model.pendingApprovals.isEmpty)
        #expect(socket.sent.count == (approvalRequested ? 3 : 2))
    }

    @Test func denyRepliesDeclined() async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_write", args: [:]))
        try await waitUntil { !model.pendingApprovals.isEmpty }

        await model.deny("c1")
        #expect(model.pendingApprovals.isEmpty)
        #expect(socket.sent.last == .toolResult(id: "c1", ok: false, content: "The owner declined this action."))
        #expect(module.calls.isEmpty)
    }

    @Test func doneClearsAWaitingCardAndALateApproveSendsNothing() async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_write", args: [:]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        socket.push(.done(text: "Timed out.", compute: "ollama", toolsUsed: []))
        try await waitUntil { model.pendingApprovals.isEmpty }

        await model.approve("c1")
        await model.deny("c1")
        #expect(socket.sent.count == 2)
        #expect(module.calls.isEmpty)
    }

    @Test func unknownToolRepliesNotOK() async throws {
        let model = makeModel()
        model.modules = [FakeToolModule()]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "nope", args: [:]))
        try await waitUntil { socket.sent.count == 3 }
        #expect(socket.sent.last == .toolResult(id: "c1", ok: false, content: "No tool named nope."))
    }

    @Test func throwingToolRepliesWithItsDescription() async throws {
        let model = makeModel()
        model.modules = [FakeToolModule()]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_fail", args: [:]))
        try await waitUntil { socket.sent.count == 3 }
        #expect(socket.sent.last == .toolResult(id: "c1", ok: false, content: "Calendar access is off."))
    }

    @Test func resultForADroppedSocketIsDropped() async throws {
        let model = makeModel()
        let module = FakeToolModule()
        model.modules = [module]
        let socket = await sendHi(model)
        socket.push(.toolCall(id: "c1", name: "fake_write", args: [:]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        socket.fail()
        try await waitUntil { model.errorMessage == "Lost connection to BT. Try again." }

        await model.approve("c1")
        #expect(socket.sent.count == 2)
    }

    @Test func errorFrameLeavesTheComposerUsable() async throws {
        let model = makeModel()
        let socket = await sendHi(model)
        socket.push(.error("Response failed. Try again."))
        try await waitUntil { model.errorMessage == "Response failed. Try again." }
        #expect(!model.isSending)

        model.draft = "Again"
        await model.send()
        #expect(socket.sent.last == .message(text: "Again", context: nil))
        #expect(factory.made.count == 1)
    }

    @Test func errorFrameReloadsHistoryToDropUnsavedMessages() async throws {
        let model = makeModel()
        await model.select("s1")
        _ = await sendHi(model)
        #expect(model.turns.count == 2)

        factory.made.last!.push(.error("Conversation is busy. Disconnect voice or wait for the current reply."))
        try await waitUntil { model.turns == api.turns }
        #expect(model.errorMessage == "Conversation is busy. Disconnect voice or wait for the current reply.")
    }

    @Test func droppedSocketReconnectsOnTheNextSend() async throws {
        let model = makeModel()
        let socket = await sendHi(model)
        socket.fail()
        try await waitUntil { model.errorMessage == "Lost connection to BT. Try again." }
        #expect(!model.isSending)

        model.draft = "Still there?"
        await model.send()
        #expect(factory.made.count == 2)
        #expect(factory.made[1].sent == [.hello(tools: []), .message(text: "Still there?", context: nil)])
    }

    @Test func failedWriteRestoresTheDraft() async {
        let model = makeModel()
        factory.failSends = true
        model.draft = "Hi"
        await model.send()

        #expect(model.draft == "Hi")
        #expect(model.turns.isEmpty)
        #expect(!model.isSending)
        #expect(model.errorMessage != nil)
    }

    @Test func blankDraftSendsNothing() async {
        let model = makeModel()
        model.draft = "   "
        await model.send()
        #expect(factory.made.isEmpty)
    }

    @Test func changingTheAddressClearsTheSelection() async {
        let model = makeModel()
        await model.select("s1")
        model.serverAddress = "http://127.0.0.1:8080"
        #expect(model.selectedSessionID == nil)

        _ = await sendHi(model)
        #expect(factory.urls.last == URL(string: "ws://127.0.0.1:8080/chat/ws")!)
    }

    @Test func retryReloadsAFailedHistory() async {
        let model = makeModel()
        api.historyFails = true
        await model.select("s1")
        #expect(model.errorMessage != nil && model.turns.isEmpty)

        api.historyFails = false
        await model.retry()
        #expect(model.turns == api.turns)
        #expect(model.errorMessage == nil)
    }

    @Test func liveStoreSendsTodayAsksToTheServerInANewConversation() async throws {
        let model = makeModel()
        await model.select("s1")
        let store = AppStore(chat: model)
        let localThreads = store.threads

        let threadID = store.sendToBT("Move CHEM review to after work")

        #expect(threadID == nil)
        #expect(store.threads == localThreads)
        #expect(model.selectedSessionID == nil)
        try await waitUntil { factory.made.last?.sent.last == .message(text: "Move CHEM review to after work", context: nil) }
        #expect(factory.urls.last == URL(string: "wss://bt.example.ts.net/chat/ws")!)
    }

    @Test func roadmapQuestionsStayInTheSameConversationAndSaveOnlyAfterApproval() async throws {
        let model = makeModel()
        let store = AppStore(chat: model)
        store.projects = [Project(id: "notes", name: "Notes", path: "", stack: "Swift")]
        model.modules = [RoadmapModule(store: store)]
        #expect(await store.draftRoadmap(projectID: "notes"))
        #expect(store.route == .bt)
        let socket = factory.made.last!
        #expect(socket.sent.first == .hello(tools: model.modules.flatMap(\.tools)))
        #expect(model.turns.first?.text.contains("Project ID: notes") == true)
        socket.push(.session(id: "roadmap-session"))
        socket.push(.done(text: "What should the first version of Notes do?", compute: "ollama", toolsUsed: []))
        try await waitUntil { !model.isSending }
        #expect(store.projects[0].stages.isEmpty)

        model.draft = "Save and search plain-text notes."
        await model.send()
        #expect(factory.made.count == 1)
        #expect(model.selectedSessionID == "roadmap-session")
        #expect(model.turns.map(\.role) == ["user", "bt", "user"])
        socket.push(.toolCall(id: "create-roadmap", name: "roadmap_create", args: [
            "project_id": "notes", "stages": [["name": "Capture", "tasks": ["Save plain-text notes"]]],
        ]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        #expect(store.projects[0].stages.isEmpty)
        await model.approve("create-roadmap")
        socket.push(.toolApproved(id: "create-roadmap"))
        try await waitUntil {
            if case .toolResult(id: "create-roadmap", ok: true, content: _) = socket.sent.last { return true }
            return false
        }
        #expect(store.projects[0].stages.first?.name == "Capture")
        #expect(model.pendingApprovals.isEmpty)
        if case let .toolResult(id, ok, _) = socket.sent.last {
            #expect(id == "create-roadmap" && ok)
        } else {
            Issue.record("No successful roadmap tool result")
        }
    }

    @Test func denyingRoadmapCreationLeavesTheProjectUnchanged() async throws {
        let model = makeModel()
        let store = AppStore(chat: model)
        store.projects = [Project(id: "notes", name: "Notes", path: "", stack: "Swift")]
        model.modules = [RoadmapModule(store: store)]
        _ = await store.draftRoadmap(projectID: "notes")
        let socket = factory.made.last!
        socket.push(.toolCall(id: "denied-roadmap", name: "roadmap_create", args: [
            "project_id": "notes", "stages": [["name": "Capture", "tasks": ["Save notes"]]],
        ]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        await model.deny("denied-roadmap")
        #expect(store.projects[0].stages.isEmpty)
    }

    @Test func startingRoadmapDoesNotInterruptAReplyOrDiscardAnUnsentDraft() async throws {
        let model = makeModel()
        let store = AppStore(chat: model)
        store.projects = [Project(id: "notes", name: "Notes", path: "", stack: "Swift")]
        model.draft = "Keep my draft"
        #expect(await store.draftRoadmap(projectID: "notes") == false)
        #expect(model.draft == "Keep my draft")
        let socket = await sendHi(model)
        let sent = socket.sent
        #expect(await store.draftRoadmap(projectID: "notes") == false)
        #expect(socket.sent == sent)
        #expect(model.isSending)
    }

    @Test(arguments: ["approve", "deny", "stale"])
    func roadmapEditsRequireApprovalAndProtectConcurrentChanges(_ decision: String) async throws {
        let model = makeModel()
        let store = AppStore(chat: model)
        store.projects = [Project(id: "notes", name: "Notes", path: "", stack: "Swift", stages: [
            RoadmapStage(id: "stage", index: 1, name: "Capture", status: .current,
                         tasks: [RoadmapTask(id: "task", title: "Save notes", status: .todo)]),
        ])]
        model.modules = [RoadmapModule(store: store)]
        #expect(await store.editRoadmap(projectID: "notes"))
        #expect(store.route == .bt)
        #expect(model.turns.first?.text.contains("Project ID: notes") == true)
        let socket = factory.made.last!
        socket.push(.toolCall(id: "read-roadmap", name: "roadmap_get", args: ["project_id": "notes"]))
        try await waitUntil { socket.sent.count == 3 }
        #expect(model.pendingApprovals.isEmpty)
        socket.push(.done(text: "What changed in the roadmap?", compute: "ollama", toolsUsed: ["roadmap_get"]))
        try await waitUntil { !model.isSending }
        model.draft = "Mark Save notes done."
        await model.send()
        socket.push(.toolCall(id: "edit-roadmap", name: "roadmap_update", args: [
            "project_id": "notes", "expected_revision": .string(try RoadmapEditing.revision(store.projects[0].stages)),
            "stages": [["id": "stage", "name": "Capture", "tasks": [["id": "task", "title": "Save notes", "status": "done"]]]],
        ]))
        try await waitUntil { !model.pendingApprovals.isEmpty }
        #expect(store.projects[0].stages[0].tasks[0].status == .todo)
        if decision == "stale" { store.projects[0].stages[0].name = "Newer manual title" }
        let before = store.projects
        if decision == "deny" {
            await model.deny("edit-roadmap")
        } else {
            await model.approve("edit-roadmap")
            socket.push(.toolApproved(id: "edit-roadmap"))
            try await waitUntil {
                if case .toolResult(id: "edit-roadmap", ok: _, content: _) = socket.sent.last { return true }
                return false
            }
        }
        #expect(model.pendingApprovals.isEmpty)
        if decision == "approve" {
            #expect(store.projects[0].stages[0].status == .done)
            #expect(store.projects[0].stages[0].progress == 1)
        } else {
            #expect(store.projects == before)
        }
        if case let .toolResult(_, ok, _) = socket.sent.last {
            #expect(ok == (decision == "approve"))
        } else { Issue.record("Missing roadmap edit tool result") }
    }

    @Test func editingRoadmapPreservesAnUnsentDraft() async {
        let model = makeModel()
        let store = AppStore(chat: model)
        store.projects = [Project(id: "notes", name: "Notes", path: "", stack: "Swift", stages: [
            RoadmapStage(index: 1, name: "Build", status: .current),
        ])]
        model.draft = "Keep this question"
        #expect(await store.editRoadmap(projectID: "notes") == false)
        #expect(model.draft == "Keep this question")
        #expect(factory.made.isEmpty)
    }

    @Test func loadingSessionsAlsoLoadsMemories() async {
        let model = makeModel()
        await model.loadSessions()
        #expect(model.memories == api.memories)
    }

    @Test func invalidAddressShowsSetupState() {
        let model = ChatModel()
        model.serverAddress = "bt.example.ts.net"
        #expect(model.endpoints == nil)
        #expect(model.errorMessage == nil)
    }
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition never became true")
}

private final class FakeChatAPI: ChatAPI, @unchecked Sendable {
    let summaries = [ChatSessionSummary(id: "s1", label: "Chemistry", updatedAt: 2)]
    let turns = [ChatTurn(id: "t1", ts: 1, role: "user", text: "Study plan", compute: nil)]

    let memories = [ServerMemory(name: "lab-room", description: "Lab is in 210", type: "user", updated: "2026-10-21T18:05:00Z")]
    var historyFails = false

    func memories() async throws -> [ServerMemory] { memories }

    func sessions() async throws -> [ChatSessionSummary] { summaries }
    func history(sessionID: String) async throws -> [ChatTurn] {
        if historyFails { throw SendFailed() }
        return turns
    }
}

private struct SendFailed: Error {}

@MainActor
private final class FakeToolModule: ToolModule {
    let id: String
    let name = "Fake"
    let symbol = "square"
    let snapshot: String?
    let tools: [ToolDefinition]
    var calls: [String] = []

    init(id: String = "fake", snapshot: String? = nil) {
        self.id = id
        self.snapshot = snapshot
        tools = [
            ToolDefinition(name: "\(id)_read", description: "Read a thing."),
            ToolDefinition(name: "\(id)_write", description: "Write a thing.", needsApproval: true),
            ToolDefinition(name: "\(id)_fail", description: "Fail."),
        ]
    }

    var content: AnyView { AnyView(EmptyView()) }

    func call(_ name: String, arguments: Data) async throws -> String {
        calls.append(name)
        switch name {
        case "\(id)_read": return "read " + String(decoding: arguments, as: UTF8.self)
        case "\(id)_write": return "wrote"
        default: throw ToolError.failed("Calendar access is off.")
        }
    }
}

private final class FakeChatSocket: ChatSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [ClientFrame] = []
    private let failSends: Bool
    private let inbox: AsyncThrowingStream<ServerFrame, any Error>
    private let continuation: AsyncThrowingStream<ServerFrame, any Error>.Continuation
    private var iterator: AsyncThrowingStream<ServerFrame, any Error>.AsyncIterator

    init(failSends: Bool) {
        self.failSends = failSends
        (inbox, continuation) = AsyncThrowingStream.makeStream()
        iterator = inbox.makeAsyncIterator()
    }

    var sent: [ClientFrame] { lock.withLock { _sent } }

    func push(_ frame: ServerFrame) { continuation.yield(frame) }
    func fail() { continuation.finish(throwing: SendFailed()) }

    func send(_ frame: ClientFrame) async throws {
        if failSends { throw SendFailed() }
        lock.withLock { _sent.append(frame) }
    }

    func receive() async throws -> ServerFrame {
        guard let frame = try await iterator.next() else { throw SendFailed() }
        return frame
    }

    func close() { continuation.finish(throwing: SendFailed()) }
}

@MainActor
private final class FakeSocketFactory {
    var made: [FakeChatSocket] = []
    var urls: [URL] = []
    var failSends = false

    func make(_ url: URL) -> any ChatSocket {
        let socket = FakeChatSocket(failSends: failSends)
        made.append(socket)
        urls.append(url)
        return socket
    }
}
