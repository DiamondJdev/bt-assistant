import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct CodingModuleTests {
    let container: ModelContainer
    let calendar = Calendar.current
    let clock: TestClock
    let module: CodingModule

    init() throws {
        container = try ModelContainer(
            for: CodingHeartbeat.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        let clock = TestClock(noon)
        self.clock = clock
        module = CodingModule(
            modelContext: container.mainContext,
            inboxDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("bt-inbox-\(UUID().uuidString)"),
            now: { clock.now }
        )
    }

    func at(dayOffset: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: clock.now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Beats every five minutes from `start` and one at `minutes`, so the session lasts `minutes + 1`.
    func seed(_ start: Date, minutes: Int, project: String = "bt-assistant", language: String = "swift") throws {
        for offset in Array(stride(from: 0, to: minutes, by: 5)) + [minutes] {
            container.mainContext.insert(CodingHeartbeat(
                timestamp: start + Double(offset * 60), editor: "vscode", project: project, language: language
            ))
        }
        try container.mainContext.save()
    }

    func call(_ name: String, _ json: String = "{}") async throws -> String {
        try await module.call(name, arguments: Data(json.utf8))
    }

    @Test func declaresReadOnlyCodingTools() {
        #expect(module.tools.map(\.name) == ["coding_get_stats", "coding_list_sessions"])
        for tool in module.tools {
            #expect(tool.name.wholeMatch(of: /coding_[a-z_]+/) != nil)
            #expect(!tool.needsApproval)
            #expect(!tool.description.isEmpty)
        }
        guard case .object(let schema) = module.tools[0].parameters,
              case .object(let properties) = schema["properties"]
        else { Issue.record("stats schema is not an object"); return }
        #expect(properties["days"] == ["type": "integer", "minimum": 1, "maximum": 30, "description": "Number of days ending today. Defaults to 7."])
    }

    @Test func snapshotWithNothingToday() throws {
        try seed(at(dayOffset: -1, hour: 9), minutes: 30)
        #expect(module.snapshot == "Coding: none today.")
    }

    @Test func snapshotWithTotalOnly() throws {
        try seed(at(hour: 8), minutes: 129)
        #expect(module.snapshot == "Coding: 2h 10m today.")
    }

    @Test func snapshotWithOpenSession() throws {
        try seed(at(hour: 9), minutes: 64, project: "web", language: "typescript")
        try seed(at(hour: 11, minute: 40), minutes: 4)
        #expect(module.snapshot == "Coding: 1h 10m today, now in bt-assistant (swift).")
    }

    @Test func getStatsDefaultsToSevenDays() async throws {
        try seed(at(hour: 9), minutes: 59)
        try seed(at(hour: 11), minutes: 29, project: "web", language: "typescript")
        try seed(at(dayOffset: -6, hour: 9), minutes: 9, project: "web", language: "swift")
        try seed(at(dayOffset: -7, hour: 9), minutes: 59, project: "old", language: "c")

        let text = try await call("coding_get_stats")

        #expect(text == """
        Coding over the past 7 days: 1h 40m.
        Per day: 2026-10-14 10m, 2026-10-15 0m, 2026-10-16 0m, 2026-10-17 0m, 2026-10-18 0m, 2026-10-19 0m, 2026-10-20 1h 30m.
        Top projects: bt-assistant 1h 0m, web 40m.
        Top languages: swift 1h 10m, typescript 30m.
        """)
    }

    @Test func getStatsForOneDay() async throws {
        try seed(at(hour: 9), minutes: 4)

        let text = try await call("coding_get_stats", #"{"days": 1}"#)

        #expect(text.hasPrefix("Coding today: 5m.\nPer day: 2026-10-20 5m."))
    }

    @Test func getStatsRejectsBadDays() async {
        for json in [#"{"days": 0}"#, #"{"days": 31}"#, #"{"days": "seven"}"#, #"{"days": 2.5}"#, "not json"] {
            await #expect(throws: ToolError.self) { try await call("coding_get_stats", json) }
        }
    }

    @Test func listSessionsDefaultsToToday() async throws {
        try seed(at(hour: 9), minutes: 59)
        try seed(at(hour: 11), minutes: 29, project: "web", language: "typescript")
        try seed(at(dayOffset: -1, hour: 9), minutes: 9)

        let text = try await call("coding_list_sessions")

        #expect(text == """
        Coding sessions on 2026-10-20:
        09:00 to 10:00, bt-assistant (swift), 1h 0m
        11:00 to 11:30, web (typescript), 30m
        """)
    }

    @Test func listSessionsForAnotherDate() async throws {
        try seed(at(dayOffset: -1, hour: 9), minutes: 9)

        #expect(try await call("coding_list_sessions", #"{"date": "2026-10-19"}"#) == """
        Coding sessions on 2026-10-19:
        09:00 to 09:10, bt-assistant (swift), 10m
        """)
        #expect(try await call("coding_list_sessions", #"{"date": "2026-10-18"}"#) == "No coding sessions on 2026-10-18.")
    }

    @Test func listSessionsRejectsBadDates() async {
        for json in [#"{"date": "yesterday"}"#, #"{"date": "2026-02-30"}"#, #"{"date": "2026-10-20T09:00"}"#, #"{"date": 20}"#] {
            await #expect(throws: ToolError.self) { try await call("coding_list_sessions", json) }
        }
    }

    @Test func unknownToolThrows() async {
        await #expect(throws: ToolError.unknownTool("coding_delete")) { try await call("coding_delete") }
    }
}
