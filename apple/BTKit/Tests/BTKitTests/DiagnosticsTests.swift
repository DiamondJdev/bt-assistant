import Foundation
import Testing
@testable import BTKit

struct DiagnosticsTests {
    @Test func decodesOptionalMetricsWithoutBreakingLegacyFrames() throws {
        let legacy = try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"done","text":"hi","compute":"ollama","tools_used":[]}"#.utf8))
        #expect(legacy == .done(text: "hi", compute: "ollama", toolsUsed: []))
        let frame = try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"metrics","turn_id":"turn-1","metrics":{"duration_ms":12,"calls":[{"call_id":"call-1","provider":"ollama","model":"test","status":"completed","prompt_tokens":80,"completion_tokens":10,"duration_ms":1000}]}}"#.utf8))
        guard case .metrics(let turnID, let metrics) = frame else {
            Issue.record("Expected metrics frame")
            return
        }
        #expect(turnID == "turn-1")
        #expect(metrics.calls?.first?.promptTokens == 80)
        #expect(metrics.calls?.first?.observedTokensPerSecond == 10)
        #expect(metrics.calls?.first?.contextPercent == nil)
    }

    @Test func malformedOptionalTelemetryDoesNotDropReply() throws {
        let frame = try ChatJSON.decoder.decode(ServerFrame.self, from: Data(#"{"type":"done","text":"hi","compute":"ollama","tools_used":[],"metrics":"invalid"}"#.utf8))
        #expect(frame == .done(text: "hi", compute: "ollama", toolsUsed: []))
    }

    @Test func diagnosticMessageIsOptIn() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.message(text: "private", context: nil))) as! [String: Any]
        #expect(plain["diagnostics"] == nil)
        let diagnostic = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClientFrame.message(text: "private", context: nil, turnID: "turn-1", diagnostics: true))) as! [String: Any]
        #expect(diagnostic["turn_id"] as? String == "turn-1")
        #expect(diagnostic["diagnostics"] as? Bool == true)
    }

    #if BT_DIAGNOSTICS
    @Test func captureIsBoundedAndIgnoresStaleTurnMetrics() throws {
        let recorder = DiagnosticsRecorder(eventLimit: 4, turnLimit: 2)
        for index in 0..<3 {
            let turnID = "turn-\(index)"
            recorder.begin(turnID: turnID)
            recorder.event(.firstText, turnID: turnID)
            recorder.finish(turnID: turnID, status: .completed)
        }
        recorder.update(turnID: "turn-0", metrics: ServerMetrics(durationMs: 999))
        let snapshot = recorder.snapshot()
        #expect(snapshot.events.count == 4)
        #expect(snapshot.turns.count == 2)
        #expect(snapshot.turns.allSatisfy { $0.server == nil })
        let exported = String(decoding: try recorder.export(), as: UTF8.self)
        #expect(!exported.contains("private"))
        #expect(exported.split(separator: "\n").allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) != nil })
    }

    @Test func disabledCaptureProducesNoRecords() {
        let recorder = DiagnosticsRecorder()
        recorder.enabled = false
        recorder.begin(turnID: "ignored")
        recorder.event(.firstText, turnID: "ignored")
        recorder.finish(turnID: "ignored", status: .failed)
        #expect(recorder.snapshot().events.isEmpty)
        #expect(recorder.snapshot().turns.isEmpty)
    }
    #endif
}
