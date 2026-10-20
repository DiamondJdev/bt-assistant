import Foundation
import Testing
@testable import BTKit

struct CodingHeartbeatTests {
    let now = Date(timeIntervalSince1970: 1_792_512_000)

    func line(ts: Double, project: String = "bt-assistant", language: String = "swift") -> String {
        #"{"ts": \#(ts), "editor": "vscode", "project": "\#(project)", "language": "\#(language)"}"#
    }

    @Test func parsesGoodLines() {
        let text = line(ts: 1_792_511_000.5) + "\n" + line(ts: 1_792_511_060, language: "python") + "\n"

        let result = parseHeartbeats(text, now: now)

        #expect(result.skipped == 0)
        #expect(result.beats == [
            Heartbeat(timestamp: Date(timeIntervalSince1970: 1_792_511_000.5), editor: "vscode", project: "bt-assistant", language: "swift"),
            Heartbeat(timestamp: Date(timeIntervalSince1970: 1_792_511_060), editor: "vscode", project: "bt-assistant", language: "python"),
        ])
    }

    @Test func badLineInTheMiddleSkipsOnlyThatLine() {
        let text = [line(ts: 1_792_511_000), "{not json", line(ts: 1_792_511_060)].joined(separator: "\n")

        let result = parseHeartbeats(text, now: now)

        #expect(result.beats.count == 2)
        #expect(result.skipped == 1)
    }

    @Test func blankLinesAndTrailingNewlineAreNotSkips() {
        let text = "\n" + line(ts: 1_792_511_000) + "\n\n  \n"

        let result = parseHeartbeats(text, now: now)

        #expect(result.beats.count == 1)
        #expect(result.skipped == 0)
    }

    @Test func rejectsTimestampsBefore2020() {
        let result = parseHeartbeats(line(ts: 1_577_836_799), now: now)
        #expect(result.beats.isEmpty)
        #expect(result.skipped == 1)
    }

    @Test func rejectsTimestampsMoreThanFiveMinutesAhead() {
        let ok = parseHeartbeats(line(ts: now.timeIntervalSince1970 + 300), now: now)
        let late = parseHeartbeats(line(ts: now.timeIntervalSince1970 + 301), now: now)
        #expect(ok.beats.count == 1)
        #expect(late.beats.isEmpty)
        #expect(late.skipped == 1)
    }

    @Test func rejectsEmptyOrLongProjects() {
        let text = [
            line(ts: 1_792_511_000, project: ""),
            line(ts: 1_792_511_000, project: String(repeating: "p", count: 201)),
            line(ts: 1_792_511_000, project: String(repeating: "p", count: 200)),
        ].joined(separator: "\n")

        let result = parseHeartbeats(text, now: now)

        #expect(result.beats.count == 1)
        #expect(result.skipped == 2)
    }

    @Test func rejectsEmptyOrLongLanguages() {
        let text = [
            line(ts: 1_792_511_000, language: ""),
            line(ts: 1_792_511_000, language: String(repeating: "l", count: 51)),
            line(ts: 1_792_511_000, language: String(repeating: "l", count: 50)),
        ].joined(separator: "\n")

        let result = parseHeartbeats(text, now: now)

        #expect(result.beats.count == 1)
        #expect(result.skipped == 2)
    }

    @Test func rejectsMissingFields() {
        let result = parseHeartbeats(#"{"ts": 1792511000, "editor": "vscode", "project": "bt"}"#, now: now)
        #expect(result.beats.isEmpty)
        #expect(result.skipped == 1)
    }
}
