import Foundation
import SwiftData
import Testing
@testable import BTKit

/// What the owner sets by hand survives a relaunch: a new `AppStore` on the same defaults.
@MainActor
struct SavedPlansTests {
    static let thursday = AppStoreTests.thursday
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let container: ModelContainer
    let clock = TestClock(AppStoreTests.thursday)

    init() throws {
        container = try ModelContainer(for: FocusSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func relaunch(code: FakeCodeSource = FakeCodeSource([])) -> AppStore {
        let clock = clock
        let pomodoro = PomodoroModule(
            modelContext: container.mainContext, defaults: defaults, notifier: FakeNotifier(), now: { clock.now }
        )
        return AppStore(clock: { clock.now }, pomodoro: pomodoro, codeSource: code, savedPlans: defaults)
    }

    private func project(_ id: String) -> Project {
        Project(id: id, name: id, path: "", stack: "swift", activity: [
            CodingActivity(start: Self.thursday - 3600, end: Self.thursday - 1800, projectID: id, source: .manual),
        ])
    }

    @Test func focusTaskAndGoalsSurvive() {
        let first = relaunch()
        first.focus.taskTitle = "Discrete HW"
        first.focus.projectID = "bt-client"
        first.focus.goals = [SessionGoal(id: "g1", title: "Problems 4–8", isDone: true)]

        let second = relaunch()

        #expect(second.focus.taskTitle == "Discrete HW")
        #expect(second.focus.projectID == "bt-client")
        #expect(second.focus.goals == [SessionGoal(id: "g1", title: "Problems 4–8", isDone: true)])
    }

    @Test func projectGoalsRoadmapsAndTrackedReposSurvive() {
        let first = relaunch(code: FakeCodeSource([project("bt-assistant")]))
        first.projects[0].weeklyGoalHours = 6
        first.projects[0].stages = [RoadmapStage(id: "s1", index: 1, name: "Calendar sync", status: .current, progress: 0.5,
                                                 tasks: [RoadmapTask(id: "t1", title: "All-day row", status: .needsYou)])]
        first.trackRepo(path: "~/dev/waypave")

        let second = relaunch(code: FakeCodeSource([project("bt-assistant")]))

        #expect(second.projects.map(\.id) == ["bt-assistant", "waypave"])
        #expect(second.projects[0].weeklyGoalHours == 6)
        #expect(second.projects[0].stages == first.projects[0].stages)
        #expect(second.projects[0].activity.count == 1)
        #expect(second.projects[1].path == "~/dev/waypave")
    }

    @Test func everyProjectIsKeptEvenWithNoRecentActivity() {
        _ = relaunch(code: FakeCodeSource([project("scratch")]))
        #expect(relaunch().projects.map(\.id) == ["scratch"])
    }

    @Test func addingAGoalAppendsAndIgnoresBlanks() {
        let store = relaunch()
        store.addFocusGoal("  Push to bt-client ")
        store.addFocusGoal("   ")
        #expect(store.focus.goals.map(\.title) == ["Push to bt-client"])
    }
}
