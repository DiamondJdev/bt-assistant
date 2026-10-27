import Foundation
import SwiftData
import Testing
@testable import BTKit

/// Coding time, focus time and projects survive quitting: a second launch on the same
/// on-disk store and defaults sees everything the first one recorded.
@MainActor
struct RelaunchTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bt-relaunch-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let clock = TestClock(AppStoreTests.thursday)

    /// One app launch: a fresh container on the same file, fresh modules, a fresh store.
    private func launch() throws -> (store: AppStore, pomodoro: PomodoroModule, coding: CodingModule, container: ModelContainer) {
        let config = ModelConfiguration(url: folder.appendingPathComponent("bt.store"))
        let container = try ModelContainer(for: Schema(BTModels.all), configurations: config)
        let clock = clock
        let pomodoro = PomodoroModule(modelContext: container.mainContext, defaults: defaults, notifier: FakeNotifier(),
                                      now: { clock.now })
        let coding = CodingModule(modelContext: container.mainContext, inboxDirectory: folder.appendingPathComponent("inbox"),
                                  now: { clock.now })
        let store = AppStore(clock: { clock.now }, pomodoro: pomodoro, codeSource: coding, savedPlans: defaults)
        return (store, pomodoro, coding, container)
    }

    /// What the VS Code extension writes: one JSON line per heartbeat.
    private func heartbeats(project: String, minutesAgo: [Int]) throws {
        let inbox = folder.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let lines = minutesAgo.map {
            #"{"ts":\#(clock.now.timeIntervalSince1970 - Double($0 * 60)),"editor":"vscode","project":"\#(project)","language":"swift"}"#
        }
        try lines.joined(separator: "\n").write(to: inbox.appendingPathComponent("beats.jsonl"), atomically: true, encoding: .utf8)
    }

    @Test func focusAndCodingTimeSurviveARelaunch() throws {
        do {
            let first = try launch()
            try heartbeats(project: "bt-assistant", minutesAgo: [60, 55, 50, 45, 40])
            first.coding.startWatching()
            first.store.toggleFocusPause()
            clock.now += 600
            first.store.endOrStartNext()
            first.store.tick()
            #expect(first.store.focusedTodaySeconds == 600)
        }

        let second = try launch()

        #expect(second.store.focusedTodaySeconds == 600)
        #expect(second.store.events.contains { $0.kind == .focusLogged && $0.duration == 600 })
        #expect(second.store.focus.mode == .break)
        let project = try #require(second.store.project("bt-assistant"))
        #expect(project.activity.reduce(0) { $0 + $1.duration } == 21 * 60)
    }

    @Test func projectsStayListedLongAfterTheirLastActivity() throws {
        do {
            let first = try launch()
            try heartbeats(project: "waypave", minutesAgo: [30, 25])
            first.coding.startWatching()
            first.store.tick()
            #expect(first.store.project("waypave") != nil)
        }
        clock.now += 90 * 86_400

        let later = try launch()

        #expect(later.store.project("waypave") != nil)
    }
}
