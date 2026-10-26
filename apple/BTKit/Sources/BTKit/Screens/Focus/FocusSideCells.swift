import SwiftUI

/// Minutes until the next event. The whole cell opens Calendar Day.
struct HardStopCell: View {
    let summary: FocusSummary
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            GridCell("Hard stop →") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(summary.hardStopMinutes.map(String.init) ?? "—")
                            .interStyle(56, .medium, tracking: -0.05)
                        if summary.hardStopMinutes != nil {
                            Text(" min").interStyle(22).foregroundStyle(Color.btMuted)
                        }
                    }
                    Text(summary.nextShortTitle.map { "until \($0)" } ?? "Nothing else today")
                        .interStyle(17, .medium)
                    if let line = summary.leaveByLine {
                        Text(line).foregroundStyle(Color.btMuted)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hard stop, open today in Calendar")
    }
}

/// Checklist bound to the session's goals, with a field to add one.
struct SessionGoalsCell: View {
    @Binding var goals: [SessionGoal]
    let label: String
    let add: (String) -> Void
    @State private var draft = ""

    var body: some View {
        GridCell("Goal for this session", meta: { Text(label) }) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach($goals) { $goal in
                    GoalRow(goal: goal) { goal.isDone.toggle() }
                }
                TextField("Add a goal", text: $draft)
                    .textFieldStyle(.plain)
                    .frame(minHeight: 32)
                    .onSubmit {
                        add(draft)
                        draft = ""
                    }
                    .accessibilityLabel("Add a goal for this session")
            }
        }
    }
}

private struct GoalRow: View {
    let goal: SessionGoal
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    Rectangle().strokeBorder(Color.btInk, lineWidth: 1)
                    if goal.isDone {
                        Rectangle().fill(Color.btInk)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.btInkOnDark)
                    }
                }
                .frame(width: 16, height: 16)
                Text(goal.title)
                    .strikethrough(goal.isDone)
                    .foregroundStyle(goal.isDone ? Color.btMuted : Color.btInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goal.title)
        .accessibilityValue(goal.isDone ? "Done" : "Not done")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Today's focused total and a tick bar against the daily goal.
struct FocusedTodayCell: View {
    let summary: FocusSummary

    var body: some View {
        GridCell("Focused today", bottom: false, meta: { Text(summary.goalLabel) }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.focusedLabel).interStyle(52, .medium, tracking: -0.045)
                TickBar(count: FocusSummary.tickCount, filled: summary.focusedTicks)
                    .accessibilityLabel("\(summary.focusedMinutes) of \(summary.goalSeconds / 60) minutes")
            }
        }
    }
}

/// One-line BT note. Opens BT.
struct BTNoteCell: View {
    let note: (plain: String, accent: String)
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            GridCell("BT →", right: false, bottom: false) {
                Text("\(note.plain) \(Text(note.accent).foregroundStyle(Color.btAccentText))")
                    .interStyle(19, .medium, tracking: -0.015)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens BT")
    }
}
