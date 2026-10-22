import Foundation

/// Text the roadmap derives from stage dates, progress and task statuses.
enum CodeRoadmapLabels {
    /// Behind schedule by more than this share of the stage reads "at risk".
    static let riskSlack = 0.1

    static func current(in project: Project) -> RoadmapStage? {
        project.stages.first { $0.status == .current }
    }

    /// "OCT 9 ✓" for done stages, "NOV" for upcoming ones, "TBD" without a date.
    static func when(_ stage: RoadmapStage, calendar: Calendar) -> String {
        switch stage.status {
        case .done:
            return stage.completedDate.map { format($0, "MMM d", calendar).uppercased() + " ✓" } ?? "✓"
        case .current, .next, .final:
            return stage.targetDate.map { format($0, "MMM", calendar).uppercased() } ?? "TBD"
        }
    }

    /// "Target Oct 30 · on track". On track means progress keeps up with the time elapsed
    /// since the previous stage finished.
    static func target(for stage: RoadmapStage, in project: Project, now: Date, calendar: Calendar) -> String {
        guard let target = stage.targetDate else { return "No target date yet" }
        let date = "Target " + format(target, "MMM d", calendar)
        if stage.progress >= 1 { return date + " · done" }
        if now > target { return date + " · overdue" }
        let started = project.stages.last { $0.index < stage.index && $0.completedDate != nil }?.completedDate
        guard let started, target > started else { return date }
        let expected = now.timeIntervalSince(started) / target.timeIntervalSince(started)
        return date + (stage.progress + riskSlack >= expected ? " · on track" : " · at risk")
    }

    static func label(_ status: RoadmapTaskStatus) -> String {
        switch status {
        case .done: "DONE"
        case .inReview: "IN REVIEW"
        case .inProgress: "IN PROGRESS"
        case .todo: "TO DO"
        case .needsYou: "NEEDS YOU"
        }
    }

    /// The open task that most needs attention: needs-you first, then review, progress, to-do.
    static func focusTask(in stage: RoadmapStage) -> RoadmapTask? {
        let order: [RoadmapTaskStatus] = [.needsYou, .inReview, .inProgress, .todo]
        return order.lazy.compactMap { status in stage.tasks.first { $0.status == status } }.first
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
