import SwiftUI

/// Focus: hard stop, goals and today's total on the left, the ring in the middle,
/// music and a BT note on the right. Matches design/screens/Focus.dc.html.
public struct FocusScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        let summary = FocusSummary(store)
        SandGrid(columns: 4, rows: [1, 1, 1], minRowHeights: [220, 220, 200]) {
            HardStopCell(summary: summary) { store.open(.calendar(.day, date: store.now)) }
                .gridCell(0, 0)
            SessionGoalsCell(goals: $store.focus.goals, label: summary.goalsLabel, add: store.addFocusGoal)
                .gridCell(0, 1)
            FocusedTodayCell(summary: summary)
                .gridCell(0, 2)
            FocusRingStage(store: store, summary: summary)
                .gridCell(1, 0, columns: 2, rows: 3)
            NowPlayingCell(store: store)
                .gridCell(3, 0, rows: 2)
            BTNoteCell(note: summary.btNote) { store.open(.bt()) }
                .gridCell(3, 2)
        }
    }
}

/// Column 4 of the header while Focus is open.
public struct FocusHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Button {
            store.doNotDisturb.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.doNotDisturb ? Color.btAccent : Color.btLine)
                    .frame(width: 7, height: 7)
                Text(store.doNotDisturb ? "Do not disturb" : "Notifications on")
                    .monoLabel(color: .btInk)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Do not disturb")
        .accessibilityValue(store.doNotDisturb ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

extension AppStore {
    /// The live track, if the music source is playing or paused on one.
    var liveMusicTrack: NowPlayingTrack? {
        if case let .playing(track) = nowPlaying?.status { return track }
        return nil
    }

    /// Breaks are quiet: stop the real player or the sample one.
    func pauseMusicForBreak() {
        if liveMusicTrack?.isPlaying == true { nowPlaying?.playPause() }
        focusScreen.samplePlaying = false
    }
}
