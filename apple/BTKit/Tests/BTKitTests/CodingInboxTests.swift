import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct CodingInboxTests {
    let container: ModelContainer
    let directory: URL
    let inbox: CodingInbox
    let now = Date(timeIntervalSince1970: 1_792_512_000)

    init() throws {
        container = try ModelContainer(
            for: CodingHeartbeat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-inbox-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
        let now = now
        inbox = CodingInbox(directory: directory, context: container.mainContext, now: { now })
    }

    func line(_ ts: Double, project: String = "bt") -> String {
        #"{"ts": \#(ts), "editor": "vscode", "project": "\#(project)", "language": "swift"}"# + "\n"
    }

    func write(_ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func stored() throws -> [CodingHeartbeat] {
        try container.mainContext.fetch(FetchDescriptor<CodingHeartbeat>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    @Test func createsMissingDirectory() throws {
        #expect(inbox.ingest() == 0)
        #expect(try files().isEmpty)
    }

    @Test func ingestsAndDeletesFiles() throws {
        try write("vscode-2026-10-20.jsonl", line(1_792_511_000) + line(1_792_511_060, project: "web"))
        try write("vscode-2026-10-19.jsonl", line(1_792_420_000))

        #expect(inbox.ingest() == 3)

        #expect(try files().isEmpty)
        let beats = try stored()
        #expect(beats.map(\.project) == ["bt", "bt", "web"])
        #expect(beats.first?.timestamp == Date(timeIntervalSince1970: 1_792_420_000))
        #expect(beats.first?.editor == "vscode")
    }

    @Test func skipsBadLines() throws {
        try write("vscode-2026-10-20.jsonl", line(1_792_511_000) + "garbage\n" + line(9_999_999_999) + line(1_792_511_060))

        #expect(inbox.ingest() == 2)
        #expect(try files().isEmpty)
    }

    @Test func picksUpLeftoverProcessingFile() throws {
        try write("vscode-2026-10-19-crashed.processing", line(1_792_420_000))

        #expect(inbox.ingest() == 1)
        #expect(try files().isEmpty)
    }

    @Test func leavesOtherFilesAlone() throws {
        try write("notes.txt", line(1_792_511_000))
        try write("vscode.json", line(1_792_511_000))

        #expect(inbox.ingest() == 0)
        #expect(try files() == ["notes.txt", "vscode.json"])
    }

    @Test func secondIngestInsertsNothing() throws {
        try write("vscode-2026-10-20.jsonl", line(1_792_511_000))

        #expect(inbox.ingest() == 1)
        #expect(inbox.ingest() == 0)
        #expect(try stored().count == 1)
    }

    @Test func callsOnIngestOnlyWhenSomethingWasInserted() throws {
        var calls = 0
        inbox.onIngest = { calls += 1 }

        _ = inbox.ingest()
        try write("vscode-2026-10-20.jsonl", line(1_792_511_000))
        _ = inbox.ingest()

        #expect(calls == 1)
    }

    @Test func defaultDirectoryIsUnderTheRealHome() {
        let path = CodingInbox.defaultDirectory().path
        #expect(path.hasSuffix("/.bt/inbox"))
        #expect(!path.contains("/Library/Containers/"))
    }
}
