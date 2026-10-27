import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct CodeActivityTests {
    static let thursday = AppStoreTests.thursday

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func project(_ name: String, _ runs: [(Date, Double)]) -> Project {
        Project(id: name.lowercased(), name: name, path: "", stack: "swift", activity: runs.map {
            CodingActivity(start: $0.0, end: $0.0 + $0.1 * 60, projectID: name.lowercased(), source: .manual)
        })
    }

    // MARK: CodingModule

    @Test func codingSessionsBecomeOneProjectEach() throws {
        let container = try ModelContainer(for: CodingHeartbeat.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = TestClock(Self.thursday)
        let module = CodingModule(
            modelContext: container.mainContext,
            inboxDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("bt-inbox-\(UUID().uuidString)"),
            now: { clock.now }
        )
        for (minute, project, language) in [(0, "BT-Assistant", "swift"), (5, "BT-Assistant", "swift"), (40, "mirai", "typescript")] {
            container.mainContext.insert(CodingHeartbeat(
                timestamp: date(22, 9, minute), editor: "vscode", project: project, language: language
            ))
        }
        try container.mainContext.save()

        let projects = module.projects(since: date(22, 0))

        #expect(projects.map(\.id) == ["bt-assistant", "mirai"])
        #expect(projects[0].name == "BT-Assistant" && projects[0].stack == "swift")
        #expect(projects[0].activity == [CodingActivity(start: date(22, 9), end: date(22, 9, 6), projectID: "bt-assistant", source: .manual)])
        #expect(projects[1].stack == "typescript")
    }

    // MARK: AppStore

    @Test func storeShowsSourceProjectsInsteadOfSamples() {
        let source = FakeCodeSource([project("bt-assistant", [(date(22, 9), 30)])])
        let store = AppStore(clock: { Self.thursday }, codeSource: source)
        #expect(store.projects.map(\.id) == ["bt-assistant"])
        #expect(store.selectedProjectID == "bt-assistant")
    }

    @Test func goalsAndTrackedReposSurviveAReload() {
        let source = FakeCodeSource([project("bt-assistant", [(date(22, 9), 30)])])
        let store = AppStore(clock: { Self.thursday }, codeSource: source)
        store.projects[0].weeklyGoalHours = 6
        store.trackRepo(path: "~/dev/waypave")
        source.projects = [project("bt-assistant", [(date(22, 9), 30), (date(22, 11), 20)])]
        source.changeToken += 1
        store.tick()
        #expect(store.projects.map(\.id) == ["bt-assistant", "waypave"])
        #expect(store.projects[0].weeklyGoalHours == 6)
        #expect(store.projects[0].activity.count == 2)
    }

    @Test func codingDuringLoggedFocusCountsAsInsideFocus() {
        // The sample week logs bt-client focus on Monday 2:00–3:40 PM.
        let source = FakeCodeSource([project("bt-client", [(date(19, 14, 30), 30), (date(19, 20), 30)])])
        let store = AppStore(clock: { Self.thursday }, codeSource: source)
        #expect(store.projects[0].activity.map { $0.insideFocusSessionID != nil } == [true, false])
    }

    // MARK: Summary

    @Test func summaryDescribesTheWeekRoadmapAndFocus() {
        let store = AppStore(clock: { Self.thursday })
        let p = store.project("bt-client")!
        let clauses = CodeSummary.clauses(project: p, week: CodeWeek(activity: p.activity, now: store.now, calendar: store.calendar))
        #expect(clauses[0] == "5h 40m this week, up 40% on your average.")
        #expect(clauses[1] == " Stage 3 is 70% done with 1 task waiting on you")
        #expect(clauses[2].hasPrefix(", and ") && clauses[2].hasSuffix("% of it happened inside Focus."))
    }

    @Test func summaryForAnIdleProjectOffersARoadmap() {
        let store = AppStore(clock: { Self.thursday })
        let p = store.project("waypave")!
        let clauses = CodeSummary.clauses(project: p, week: CodeWeek(activity: p.activity, now: store.now, calendar: store.calendar))
        #expect(clauses == ["No activity in 9 days.", " There’s no roadmap yet", " — want me to draft one from the repo?"])
    }
}

@MainActor
final class FakeCodeSource: CodeActivitySource {
    var projects: [Project]
    var changeToken = 0

    init(_ projects: [Project]) { self.projects = projects }

    func projects(since start: Date) -> [Project] { projects }
}
