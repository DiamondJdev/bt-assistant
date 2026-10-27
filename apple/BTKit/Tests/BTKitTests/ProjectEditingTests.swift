import Foundation
import Testing
@testable import BTKit

/// Editing a project's details and removing a tracked project from the Code screen.
@MainActor
struct ProjectEditingTests {
    func date(_ day: Int, _ hour: Int) -> Date {
        Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func project(_ id: String, minutes: Double = 30) -> Project {
        Project(id: id, name: id, path: "", stack: "swift",
                activity: [CodingActivity(start: date(22, 9), end: date(22, 9).addingTimeInterval(minutes * 60), projectID: id, source: .manual)])
    }

    @Test func updateTrimsAndSavesDetails() throws {
        let store = AppStore(clock: { AppStoreTests.thursday })
        try store.updateProject("waypave", name: "  Waypave  ", path: " ~/dev/waypave ", weeklyGoalHours: 3)
        let p = try #require(store.project("waypave"))
        #expect(p.name == "Waypave")
        #expect(p.path == "~/dev/waypave")
        #expect(p.weeklyGoalHours == 3)
        try store.updateProject("waypave", name: "Waypave", path: "", weeklyGoalHours: nil)
        #expect(store.project("waypave")?.weeklyGoalHours == nil)
    }

    @Test func updateRejectsBadDetails() {
        let store = AppStore(clock: { AppStoreTests.thursday })
        #expect(throws: ToolError.self) { try store.updateProject("waypave", name: "  ", path: "", weeklyGoalHours: nil) }
        #expect(throws: ToolError.self) { try store.updateProject("waypave", name: "W", path: "", weeklyGoalHours: 0) }
        #expect(throws: ToolError.self) { try store.updateProject("waypave", name: "W", path: "", weeklyGoalHours: 200) }
        #expect(throws: ToolError.self) { try store.updateProject("missing", name: "W", path: "", weeklyGoalHours: nil) }
        #expect(store.project("waypave")?.name == "waypave")
    }

    @Test func removeDropsAProjectAndClearsReferences() {
        let store = AppStore(clock: { AppStoreTests.thursday })
        store.selectedProjectID = "waypave"
        store.removeProject("waypave")
        #expect(store.project("waypave") == nil)
        #expect(store.selectedProjectID == nil)
    }

    @Test func trackingAHeartbeatProjectAttachesItsFolder() {
        let source = FakeCodeSource([project("bt-assistant")])
        let store = AppStore(clock: { AppStoreTests.thursday }, codeSource: source)
        #expect(store.trackRepo(path: "/Users/me/Documents/bt-assistant", bookmark: Data([1])))
        #expect(store.projects.map(\.id) == ["bt-assistant"])
        #expect(store.projects[0].path == "/Users/me/Documents/bt-assistant")
        #expect(store.projects[0].bookmark == Data([1]))
        #expect(store.projects[0].activity.count == 1)
    }

    @Test func trackingTheSameFolderTwiceSelectsIt() {
        let store = AppStore(clock: { AppStoreTests.thursday })
        #expect(store.trackRepo(path: "/Users/me/dev/notes"))
        store.selectedProjectID = "waypave"
        #expect(!store.trackRepo(path: "/Users/me/dev/notes/"))
        #expect(store.projects.filter { $0.name == "notes" }.count == 1)
        #expect(store.selectedProjectID == "notes")
    }

    @Test func bookmarkSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppStore(clock: { AppStoreTests.thursday }, codeSource: FakeCodeSource([]), savedPlans: defaults)
        first.trackRepo(path: "/Users/me/dev/notes", bookmark: Data([7]))
        let second = AppStore(clock: { AppStoreTests.thursday }, codeSource: FakeCodeSource([]), savedPlans: defaults)
        #expect(second.project("notes")?.bookmark == Data([7]))
    }

    @Test func removedDuplicateStaysGone() {
        let source = FakeCodeSource([project("bt-assistant")])
        let store = AppStore(clock: { AppStoreTests.thursday }, codeSource: source)
        store.trackRepo(path: "~/Documents/bt-assistant")
        store.trackRepo(path: "~/old/bt-assistant")
        #expect(store.projects.map(\.id) == ["bt-assistant", "bt-assistant-2"])
        store.removeProject("bt-assistant-2")
        source.changeToken += 1
        store.tick()
        #expect(store.projects.map(\.id) == ["bt-assistant"])
    }

    @Test func removedProjectWithActivityStaysHiddenUntilTrackedAgain() {
        let source = FakeCodeSource([project("bt-assistant")])
        let store = AppStore(clock: { AppStoreTests.thursday }, codeSource: source)
        store.removeProject("bt-assistant")
        source.changeToken += 1
        store.tick()
        #expect(store.projects.isEmpty)
        store.trackRepo(path: "~/Documents/bt-assistant")
        source.changeToken += 1
        store.tick()
        #expect(store.projects.map(\.id) == ["bt-assistant"])
        #expect(store.projects[0].activity.count == 1)
    }

    @Test func renameSurvivesAReload() throws {
        let source = FakeCodeSource([project("bt-assistant")])
        let store = AppStore(clock: { AppStoreTests.thursday }, codeSource: source)
        try store.updateProject("bt-assistant", name: "BT", path: "", weeklyGoalHours: nil)
        source.changeToken += 1
        store.tick()
        #expect(store.project("bt-assistant")?.name == "BT")
    }

    @Test func removalAndRenameSurviveARelaunch() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let source = FakeCodeSource([project("bt-assistant"), project("djcli")])
        let first = AppStore(clock: { AppStoreTests.thursday }, codeSource: source, savedPlans: defaults)
        first.removeProject("djcli")
        try first.updateProject("bt-assistant", name: "BT", path: "~/Documents/bt-assistant", weeklyGoalHours: 12)

        let second = AppStore(clock: { AppStoreTests.thursday }, codeSource: source, savedPlans: defaults)
        #expect(second.projects.map(\.id) == ["bt-assistant"])
        #expect(second.project("bt-assistant")?.name == "BT")
        #expect(second.project("bt-assistant")?.weeklyGoalHours == 12)
    }

    @Test func oldSavedPlansWithoutHiddenProjectsStillLoad() throws {
        let json = #"{"focus":{"taskTitle":"Focus","goals":[]},"projects":[{"id":"a","name":"a","path":"","stack":"","stages":[]}]}"#
        let plans = try JSONDecoder().decode(SavedPlans.self, from: Data(json.utf8))
        #expect(plans.savedProjects.map(\.id) == ["a"])
        #expect(plans.hiddenProjectIDs == nil)
    }
}
