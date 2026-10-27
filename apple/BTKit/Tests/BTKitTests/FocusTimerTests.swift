import Foundation
import SwiftData
import Testing
@testable import BTKit

/// AppStore's focus session driven by the real `PomodoroModule`.
@MainActor
struct FocusTimerTests {
    let container: ModelContainer
    let clock = TestClock(AppStoreTests.thursday)
    let pomodoro: PomodoroModule
    let store: AppStore

    init() throws {
        container = try ModelContainer(for: FocusSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = clock
        pomodoro = PomodoroModule(
            modelContext: container.mainContext, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            notifier: FakeNotifier(), now: { clock.now }
        )
        store = AppStore(clock: { clock.now }, pomodoro: pomodoro)
    }

    private func advance(_ seconds: TimeInterval) {
        clock.now += seconds
        store.tick()
    }

    @Test func idleTimerShowsAWaitingWorkPhase() {
        #expect(store.focus.mode == .focus)
        #expect(store.focus.isPaused)
        #expect(store.focus.remainingSeconds == 1500)
        #expect(store.focus.goals.isEmpty)
        #expect(store.focusedTodaySeconds == 0)
    }

    @Test func pauseButtonStartsTheSharedTimer() {
        store.toggleFocusPause()
        #expect(pomodoro.state.isRunning)
        advance(100)
        #expect(store.focus.remainingSeconds == 1400)
        #expect(!store.focus.isPaused)
        #expect(store.focusedTodaySeconds == 100)
    }

    @Test func menuBarPauseShowsOnTheFocusScreen() {
        store.toggleFocusPause()
        pomodoro.pause()
        advance(1)
        #expect(store.focus.isPaused)
    }

    @Test func plusFiveMinutesExtendsTheRunningPhase() {
        store.toggleFocusPause()
        advance(100)
        store.addFiveMinutes()
        #expect(store.focus.remainingSeconds == 1700)
        #expect(store.focus.plannedSeconds == 1800)
        #expect(pomodoro.state.endsAt == AppStoreTests.thursday + 1800)
    }

    @Test func endSessionLogsFocusAndRunsTheBreak() {
        store.toggleFocusPause()
        advance(600)
        store.endOrStartNext()
        #expect(store.focus.mode == .break)
        #expect(pomodoro.state.isRunning)
        #expect(store.focusedTodaySeconds == 600)
        let logged = store.events.filter { $0.kind == .focusLogged && $0.start == AppStoreTests.thursday }
        #expect(logged.map(\.duration) == [600])
    }

    @Test func blockStartsFocusWithItsPlanAndTitle() {
        let block = store.event("f2")!
        store.startFocus(from: block)
        #expect(store.focus.taskTitle == "bt-client deep work")
        #expect(store.focus.plannedSeconds == 50 * 60)
        #expect(pomodoro.state.isRunning)
        advance(120)
        store.endOrStartNext()
        #expect(store.events.contains { $0.kind == .focusLogged && $0.title == "bt-client deep work" })
    }
}
