import Foundation
import Testing
@testable import BTKit

struct PomodoroTimerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let durations = PomodoroDurations()

    @Test func startSetsEndsAtFromWorkDuration() {
        let state = PomodoroState.idle.started(at: t0, durations: durations)

        #expect(state.phase == .work)
        #expect(state.endsAt == t0 + 1500)
        #expect(state.isRunning)
    }

    @Test func extendingAddsToRunningAndPausedPhasesOnly() {
        let running = PomodoroState.idle.started(at: t0, durations: durations).extended(by: 300)
        #expect(running.endsAt == t0 + 1800)
        #expect(running.phaseDuration == 1800)
        let paused = PomodoroState.idle.started(at: t0, durations: durations).paused(at: t0 + 100).extended(by: 300)
        #expect(paused.pausedRemaining == 1700)
        #expect(paused.resumed(at: t0 + 200).startedAt == t0 + 100)
        #expect(PomodoroState.idle.extended(by: 300) == .idle)
    }

    @Test func completingWorkGoesToShortBreakAndReportsInterval() {
        let (state, interval) = PomodoroState.idle.started(at: t0, durations: durations)
            .completed(durations: durations)

        #expect(state.phase == .shortBreak)
        #expect(state.endsAt == nil)
        #expect(!state.isRunning)
        #expect(state.completedWorkPhases == 1)
        #expect(interval == FocusInterval(start: t0, end: t0 + 1500))
    }

    @Test func fourthWorkPhaseLeadsToLongBreak() {
        var state = PomodoroState.idle
        for round in 1...4 {
            state = state.started(at: t0, durations: durations).completed(durations: durations).0
            #expect(state.phase == (round == 4 ? .longBreak : .shortBreak))
            if round < 4 {
                state = state.started(at: t0, durations: durations).completed(durations: durations).0
                #expect(state.phase == .work)
            }
        }

        let (afterLong, interval) = state.started(at: t0, durations: durations).completed(durations: durations)

        #expect(afterLong.phase == .work)
        #expect(interval == nil)
    }

    @Test func pauseKeepsRemainingAndResumeRestoresIt() {
        let paused = PomodoroState.idle.started(at: t0, durations: durations).paused(at: t0 + 100)

        #expect(paused.pausedRemaining == 1400)
        #expect(paused.endsAt == nil)
        #expect(paused.isPaused)
        #expect(paused.remaining(at: t0 + 300) == 1400)

        let resumed = paused.resumed(at: t0 + 500)

        #expect(resumed.endsAt == t0 + 1900)
        #expect(resumed.pausedRemaining == nil)
        #expect(resumed.isRunning)
    }

    @Test func stopUnderSixtySecondsLogsNothing() {
        let (state, interval) = PomodoroState.idle.started(at: t0, durations: durations).stopped(at: t0 + 59)

        #expect(interval == nil)
        #expect(state == .idle)
        #expect(state.phase == .work)
    }

    @Test func stopAfterSixtySecondsLogsPartialWork() {
        let (_, interval) = PomodoroState.idle.started(at: t0, durations: durations).stopped(at: t0 + 600)

        #expect(interval == FocusInterval(start: t0, end: t0 + 600))
    }

    @Test func stoppingABreakLogsNothing() {
        let onBreak = PomodoroState.idle.started(at: t0, durations: durations)
            .completed(durations: durations).0
            .started(at: t0 + 1500, durations: durations)

        let (state, interval) = onBreak.stopped(at: t0 + 1700)

        #expect(interval == nil)
        #expect(state == .idle)
    }

    @Test func skippingWorkLogsElapsedLikeStop() {
        let running = PomodoroState.idle.started(at: t0, durations: durations)

        let (short, none) = running.skipped(at: t0 + 30, durations: durations)
        #expect(none == nil)
        #expect(short.phase == .shortBreak)
        #expect(!short.isRunning)

        let (_, interval) = running.skipped(at: t0 + 600, durations: durations)
        #expect(interval == FocusInterval(start: t0, end: t0 + 600))
    }

    @Test func changingDurationsDoesNotMoveRunningPhase() {
        let running = PomodoroState.idle.started(at: t0, durations: durations)
        var shorter = durations
        shorter.work = 60
        shorter.shortBreak = 30

        let restarted = running.started(at: t0 + 10, durations: shorter)
        #expect(restarted.endsAt == t0 + 1500)

        let nextBreak = running.completed(durations: shorter).0.started(at: t0 + 1500, durations: shorter)
        #expect(nextBreak.endsAt == t0 + 1530)
    }

    @Test func stoppingPausedWorkLogsRunningTimeOnly() {
        let paused = PomodoroState.idle.started(at: t0, durations: durations).paused(at: t0 + 400)

        let (_, interval) = paused.stopped(at: t0 + 5000)

        #expect(interval == FocusInterval(start: t0, end: t0 + (1500 - 1100)))
    }

    @Test func stoppingResumedWorkExcludesPausedTime() {
        let resumed = PomodoroState.idle.started(at: t0, durations: durations)
            .paused(at: t0 + 100)
            .resumed(at: t0 + 1000)

        let (_, interval) = resumed.stopped(at: t0 + 1200)

        #expect(interval.map { $0.end.timeIntervalSince($0.start) } == 300)
    }

    @Test func durationsDecodeMissingFieldsAsDefaults() throws {
        let decoded = try JSONDecoder().decode(PomodoroDurations.self, from: Data(#"{"work":600}"#.utf8))

        #expect(decoded.work == 600)
        #expect(decoded.shortBreak == 300)
        #expect(decoded.longBreak == 900)
        #expect(decoded.longBreakEvery == 4)
    }
}
