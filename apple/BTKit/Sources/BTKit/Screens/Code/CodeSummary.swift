import Foundation

/// BT's three-clause weekly summary for a project (ink, muted, muted), built from its activity and roadmap.
enum CodeSummary {
    static func clauses(project: Project, week: CodeWeek) -> [String] {
        let stage = project.stages.first { $0.status == .current }
        return [weekClause(week), stage.map(stageClause) ?? " There’s no roadmap yet", focusClause(stage: stage, week: week)]
    }

    private static func weekClause(_ week: CodeWeek) -> String {
        guard week.weekMinutes > 0 else {
            switch week.status {
            case .idle(let days): return "No activity in \(days) days."
            case .noActivity: return "Nothing tracked yet."
            default: return "Nothing yet this week."
            }
        }
        let total = BTFormat.duration(week.weekMinutes * 60) + " this week"
        guard let average = week.averageMinutes else { return total + "." }
        let change = Int(((week.weekMinutes / average - 1) * 100).rounded())
        return total + ", \(change < 0 ? "down" : "up") \(abs(change))% on your average."
    }

    private static func stageClause(_ stage: RoadmapStage) -> String {
        let waiting = stage.tasks.filter { $0.status == .needsYou }.count
        let base = " Stage \(stage.index) is \(BTFormat.percent(stage.progress)) done"
        return waiting == 0 ? base : base + " with \(waiting) task\(waiting == 1 ? "" : "s") waiting on you"
    }

    private static func focusClause(stage: RoadmapStage?, week: CodeWeek) -> String {
        guard stage != nil else { return " — want me to draft one from the repo?" }
        guard let share = week.insideShare else { return "." }
        return ", and \(BTFormat.percent(share)) of it happened inside Focus."
    }
}
