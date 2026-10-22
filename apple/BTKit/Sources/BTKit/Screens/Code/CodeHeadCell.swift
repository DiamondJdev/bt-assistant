import SwiftUI

/// Columns 2–4, row 1: path line, the 80pt project name, stats, and BT's summary with notes 1 2 3.
struct CodeHeadCell: View {
    let project: Project
    let week: CodeWeek

    var body: some View {
        let copy = CodeSampleCopy.copy(for: project.id)
        GeometryReader { g in
            let left = (g.size.width - 32) / 2.25
            HStack(alignment: .bottom, spacing: 32) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(pathLine).monoLabel().lineLimit(1)
                    Text(project.name)
                        .interStyle(80, .medium, tracking: -0.055)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: 68, alignment: .bottom)
                    HStack(spacing: 32) {
                        stat(CodeWeek.duration(minutes: week.weekMinutes), "This week")
                        stat(streak, "Streak")
                        stat(copy.commits, "Commits")
                    }
                }
                .frame(width: left, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    Text("BT · \(project.name) this week").monoLabel()
                    summary(copy.clauses)
                        .font(.inter(24, .medium))
                        .tracking(24 * -0.02)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dashedEdges(right: false, bottom: false, left: true)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(BTMetrics.cellPadding)
        .dashedEdges(right: false, bottom: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name) this week")
    }

    /// "Swift · ~/dev/bt-client · main"
    private var pathLine: String {
        ([project.stack, project.path] + (project.branch.map { [$0] } ?? [])).joined(separator: " · ")
    }

    private var streak: String {
        let days = week.streakDays
        return days == 0 ? "—" : "\(days) day\(days == 1 ? "" : "s")"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).interStyle(26, .medium, tracking: -0.04)
            Text(label).monoLabel(10, tracking: 0.06)
        }
    }

    /// Ink, muted, muted clauses, each followed by its accent note number.
    private func summary(_ clauses: [String]) -> Text {
        clauses.enumerated().reduce(Text("")) { text, item in
            let (i, clause) = item
            let note = Text("\(i + 1)").font(.mono(11)).foregroundStyle(Color.btAccentText).baselineOffset(10)
            return text + Text(clause).foregroundStyle(i == 0 ? Color.btInk : Color.btMuted) + note
        }
    }
}
