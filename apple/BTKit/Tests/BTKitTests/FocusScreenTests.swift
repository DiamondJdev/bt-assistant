import Foundation
import Observation
import Testing
@testable import BTKit

@MainActor
struct FocusScreenTests {
    /// Thursday 22 Oct 2026, 12:46. The next class (Discrete Math) is at 1:30.
    static let thursday = Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12, minute: 46))!

    func makeStore() -> AppStore { AppStore(clock: { Self.thursday }) }

    @Test func hardStopCountsMinutesToNextClass() {
        let s = FocusSummary(makeStore())
        #expect(s.hardStopMinutes == 44)
        #expect(s.nextShortTitle == "Discrete Math")
        #expect(s.leaveByLine == "Leave by 1:20 · [Room]")
        #expect(s.nextEventLabel == "Class at 1:30")
    }

    @Test func noNextEventFallsBack() {
        let store = makeStore()
        store.events = []
        let s = FocusSummary(store)
        #expect(s.hardStopMinutes == nil)
        #expect(s.nextEventLabel == "Nothing else today")
        #expect(s.btNote.accent == "Nothing else is on today.")
    }

    @Test func focusLabels() {
        let s = FocusSummary(makeStore())
        #expect(s.sessionLabel == "Session 2 of 4")
        #expect(s.taskLabel == "Calendar sync module")
        // 1122s left from 12:46:00 → 13:04:42.
        #expect(s.nextStepLabel == "Break at 1:04")
        #expect(s.ofLabel == "of 25:00")
        #expect(!s.ofIsAlert)
        #expect(s.pauseLabel == "Pause")
        #expect(s.endLabel == "End session")
        #expect(s.btNote.accent == "remind you to leave by 1:20.")
    }

    @Test func pausedLabels() {
        let store = makeStore()
        store.toggleFocusPause()
        let s = FocusSummary(store)
        #expect(s.ofLabel == "Paused · of 25:00")
        #expect(s.ofIsAlert)
        #expect(s.pauseLabel == "Resume")
    }

    @Test func breakLabels() {
        let store = makeStore()
        store.endOrStartNext()
        let s = FocusSummary(store)
        #expect(s.sessionLabel == "Break · 5 min")
        #expect(s.taskLabel == "Stand up, water, no phone")
        #expect(s.nextStepLabel == "Session 3 next")
        #expect(s.endLabel == "Start session 3")
        #expect(s.btNote.plain == "Music is paused for your break.")
        #expect(s.btNote.accent == "Leave for class by 1:20.")
    }

    @Test func finishedBreakSaysBreakOver() {
        let store = makeStore()
        store.endOrStartNext()
        store.focus.remainingSeconds = 0
        #expect(FocusSummary(store).ofLabel == "Break over")
    }

    @Test func focusedTodayAgainstGoal() {
        let store = makeStore()
        #expect(FocusSummary(store).focusedLabel == "0h 31m")
        #expect(FocusSummary(store).focusedTicks == 6)
        #expect(FocusSummary(store).goalsLabel == "1 of 3 done")
        store.focusedTodaySeconds = 3 * 3600
        #expect(FocusSummary(store).focusedTicks == 24)
    }

    @Test func timeIsTwelveHour() {
        let s = FocusSummary(makeStore())
        let midnight = Calendar.bt.startOfDay(for: Self.thursday)
        #expect(s.time(midnight) == "12:00")
        #expect(s.time(midnight.addingTimeInterval(13 * 3600 + 5 * 60)) == "1:05")
    }

    @Test func playbackWrapsToNextTrack() {
        let state = FocusScreenState()
        state.position = FocusScreenState.trackLength - 1
        state.advance(playing: true)
        #expect(state.position == 0)
        #expect(state.track == 4)
        state.advance(playing: false)
        #expect(state.position == 0)
    }

    @Test func skipWrapsAround() {
        let state = FocusScreenState()
        state.track = 0
        state.position = 50
        state.skip(by: -1)
        #expect(state.track == FocusScreenState.trackCount - 1)
        #expect(state.position == 0)
    }

    @Test func levelsFlatWhenStopped() {
        let state = FocusScreenState()
        #expect(state.levels(playing: false).allSatisfy { $0 == 4 })
        #expect(state.levels(playing: true).count == 32)
        #expect(state.levels(playing: true).allSatisfy { (6...34).contains($0) })
    }

    @Test func breakPausesSampleMusic() {
        let store = makeStore()
        store.pauseMusicForBreak()
        #expect(!store.focusScreen.samplePlaying)
    }

    @Test func breakPausesLiveMusicOnlyWhenPlaying() {
        let source = FakeMusic(isPlaying: true)
        let store = AppStore(clock: { Self.thursday }, nowPlaying: source)
        store.pauseMusicForBreak()
        #expect(source.toggles == 1)
        source.status = .playing(NowPlayingTrack(title: "T", artist: "A", artwork: nil, isPlaying: false))
        store.pauseMusicForBreak()
        #expect(source.toggles == 1)
    }
}

@MainActor
@Observable
private final class FakeMusic: NowPlayingSource {
    var status: NowPlayingStatus
    var toggles = 0
    init(isPlaying: Bool) {
        status = .playing(NowPlayingTrack(title: "T", artist: "A", artwork: nil, isPlaying: isPlaying))
    }
    func playPause() { toggles += 1 }
    func next() {}
    func previous() {}
    func openMusic() {}
}
