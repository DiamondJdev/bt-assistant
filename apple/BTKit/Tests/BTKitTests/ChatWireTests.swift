import Foundation
import Testing
@testable import BTKit

struct ChatWireTests {
    private func frame(_ json: String) throws -> ServerFrame {
        try ChatJSON.decoder.decode(ServerFrame.self, from: Data(json.utf8))
    }

    private func object(_ frame: ClientFrame) throws -> NSDictionary {
        let data = try JSONEncoder().encode(frame)
        return try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func decodesEveryServerFrame() throws {
        #expect(try frame(#"{"type":"session","session_id":"s1"}"#) == .session(id: "s1"))
        #expect(try frame(#"{"type":"delta","text":"Hel"}"#) == .delta("Hel"))
        #expect(try frame(#"{"type":"tool_call","id":"c1","name":"calendar_list_events","args":{}}"#) == .unknown)
        #expect(try frame(#"{"type":"done","text":"Hello","compute":"ollama","tools_used":["memory_search"]}"#)
            == .done(text: "Hello", compute: "ollama", toolsUsed: ["memory_search"]))
        #expect(try frame(#"{"type":"error","message":"Wait for the current reply."}"#)
            == .error("Wait for the current reply."))
        #expect(try frame(#"{"type":"reset"}"#) == .unknown)
    }

    @Test func encodesClientFramesInTheServerShape() throws {
        #expect(try object(.message(text: "Hi", context: nil)) == ["type": "message", "text": "Hi"] as NSDictionary)
        #expect(try object(.message(text: "Hi", context: "Pomodoro idle"))
            == ["type": "message", "text": "Hi", "context": "Pomodoro idle"] as NSDictionary)
    }

    @Test func endpointsHandleTrailingSlashesAndSchemes() throws {
        let e = try #require(ChatEndpoints(serverAddress: "https://bt.example.ts.net/"))
        #expect(e.socketURL(sessionID: nil).absoluteString == "wss://bt.example.ts.net/chat/ws")
        #expect(e.socketURL(sessionID: "s 1").absoluteString == "wss://bt.example.ts.net/chat/ws?session_id=s%201")
        #expect(e.historyURL(sessionID: "s1").absoluteString == "https://bt.example.ts.net/history?session_id=s1")
        let local = try #require(ChatEndpoints(serverAddress: " http://127.0.0.1:8080 "))
        #expect(local.sessionsURL.absoluteString == "http://127.0.0.1:8080/sessions")
        #expect(local.socketURL(sessionID: nil).absoluteString == "ws://127.0.0.1:8080/chat/ws")
        #expect(ChatEndpoints(serverAddress: "bt.example.ts.net") == nil)
        #expect(ChatEndpoints(serverAddress: "ftp://x") == nil)
        #expect(ChatEndpoints(serverAddress: "") == nil)
    }

    @Test func decodesSessionsAndHistoryFromServerJSON() throws {
        let sessions = try ChatJSON.decoder.decode([ChatSessionSummary].self, from: Data(#"""
            [{"id":"s1","label":"Chemistry","updated_at":1760900000.5}]
            """#.utf8))
        #expect(sessions == [ChatSessionSummary(id: "s1", label: "Chemistry", updatedAt: 1760900000.5)])

        let turns = try ChatJSON.decoder.decode([ChatTurn].self, from: Data(#"""
            [{"id":"t1","session_id":"s1","ts":1.0,"role":"user","text":"Hi","input_mode":"text","compute":null,"context":"x"},
             {"id":"t2","session_id":"s1","ts":2.0,"role":"bt","text":"Hello","input_mode":null,"compute":"openai"}]
            """#.utf8))
        #expect(turns == [
            ChatTurn(id: "t1", ts: 1, role: "user", text: "Hi", compute: nil),
            ChatTurn(id: "t2", ts: 2, role: "bt", text: "Hello", compute: "openai"),
        ])
    }

    @Test func serverErrorsCarryTheDetail() {
        #expect(ChatServerError(status: 404, body: Data(#"{"detail":"Conversation not found"}"#.utf8)).message
            == "Conversation not found")
        #expect(ChatServerError(status: 500, body: Data("oops".utf8)).message == "BT server error (500).")
    }
}
