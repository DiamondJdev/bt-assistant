import Foundation
import SwiftData
import Testing
@testable import BTKit

@MainActor
struct PomodoroModuleTests {
    let container: ModelContainer
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let notifier = FakeNotifier()
    let clock = TestClock(Date(timeIntervalSinceReferenceDate: 1_000_000))

    init() throws {
        container = try ModelContainer(
            for: FocusSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func makeModule() -> PomodoroModule {
        let clock = clock
        return PomodoroModule(
            modelContext: container.mainContext,
            defaults: defaults,
            notifier: notifier,
            now: { clock.now }
        )
    }

    func sessions() throws -> [FocusSession] {
        try container.mainContext.fetch(FetchDescriptor<FocusSession>())
    }

    @Test func startSchedulesNotificationAtEndsAt() async {
        let module = makeModule()

        module.start()
        await module.notificationsSettled()

        #expect(module.state.endsAt == clock.now + 1500)
        #expect(await notifier.calls == [.schedule(.work, clock.now + 1500)])
    }

    @Test func pauseRemovesNotificationAndResumeReschedules() async {
        let module = makeModule()
        let t0 = clock.now
        module.start()
        clock.now = t0 + 100
        module.pause()
        clock.now = t0 + 400
        module.resume()
        await module.notificationsSettled()

        #expect(module.state.remaining(at: clock.now) == 1400)
        #expect(await notifier.calls == [
            .schedule(.work, t0 + 1500),
            .cancel,
            .schedule(.work, t0 + 1800),
        ])
    }

    @Test func tickPastEndLogsWorkOnceAndAdvances() throws {
        let module = makeModule()
        module.start()
        clock.now += 1501

        module.tick()
        module.tick()

        #expect(try sessions().count == 1)
        #expect(module.state.phase == .shortBreak)
        #expect(!module.state.isRunning)
    }

    @Test func stopLogsPartialWorkAndCancels() async throws {
        let module = makeModule()
        module.start()
        clock.now += 600

        module.stop()
        await module.notificationsSettled()

        #expect(try sessions().first?.focusedSeconds == 600)
        #expect(module.state == .idle)
        #expect(await notifier.calls.last == .cancel)
    }

    @Test func stateSurvivesRecreatingModule() {
        let first = makeModule()
        first.start()
        var durations = first.durations
        durations.work = 600
        first.durations = durations

        let second = makeModule()

        #expect(second.state.endsAt == first.state.endsAt)
        #expect(second.durations.work == 600)
    }

    @Test func recoversPhaseThatEndedWhileClosed() throws {
        let first = makeModule()
        first.start()
        let endsAt = try #require(first.state.endsAt)
        clock.now = endsAt + 3600

        let second = makeModule()
        #expect(try sessions().count == 1)
        #expect(try sessions().first?.end == endsAt)
        #expect(second.state.phase == .shortBreak)

        _ = makeModule()
        #expect(try sessions().count == 1)
    }

    @Test func snapshotFormats() throws {
        let module = makeModule()
        try FocusLog(context: container.mainContext)
            .record(FocusInterval(start: clock.now - 6000, end: clock.now - 300), label: nil)

        #expect(module.snapshot == "Focus: idle, 1h 35m focused today.")
        #expect(module.menuBarTitle == nil)

        module.start()
        clock.now += 1500 - 720

        #expect(module.snapshot == "Focus: work phase, 12m left, 1h 35m focused today.")
        #expect(module.menuBarTitle == "12:00")

        module.pause()

        #expect(module.snapshot == "Focus: work phase paused, 12m left, 1h 35m focused today.")
    }

    @Test func declaresFocusTools() {
        #expect(makeModule().tools.map(\.name) == [
            "focus_get_status", "focus_start", "focus_pause", "focus_stop", "focus_get_stats",
        ])
    }

    @Test func nowPlayingStatusMessages() {
        let track = NowPlayingTrack(title: "Song", artist: "Artist", artwork: nil, isPlaying: true)

        #expect(NowPlayingStatus.notRunning.message == "Music isn't open.")
        #expect(NowPlayingStatus.notPermitted.message
            == "Allow BT to control Music in System Settings › Privacy & Security › Automation.")
        #expect(NowPlayingStatus.stopped.message == "Nothing playing.")
        #expect(NowPlayingStatus.playing(track).message == nil)
    }
}

final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

actor FakeNotifier: PhaseNotifier {
    enum Call: Equatable {
        case schedule(PomodoroPhase, Date)
        case cancel
    }

    private(set) var calls: [Call] = []

    func schedule(phase: PomodoroPhase, at date: Date) {
        calls.append(.schedule(phase, date))
    }

    func cancelAll() {
        calls.append(.cancel)
    }
}
