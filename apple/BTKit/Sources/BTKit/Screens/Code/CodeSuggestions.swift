import Foundation

/// One "BT suggests" row: a sentence, a button, and the write the button performs.
public struct CodeSuggestion: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// A `studyPlanned` block linked to the project.
        case book(start: Date, end: Date, title: String)
        /// A goal appended to the running Focus session.
        case focusGoal(String)
        case weeklyGoal(hours: Double)
        /// Asks BT to draft stages in a new thread.
        case draftRoadmap
    }

    public var title: String
    public var label: String
    public var doneLabel: String
    public var action: Action
}

enum CodeSuggestions {
    static let defaultGoalHours = 3.0
    static let maxBlockHours = 2
    static let weekendHour = 10

    /// Minutes logged this week plus blocks still booked for the project later this week.
    static func bookedMinutes(_ project: Project, week: CodeWeek, events: [CalendarEvent]) -> Double {
        let ahead = events.filter {
            $0.linkedProjectID == project.id && ($0.kind == .studyPlanned || $0.kind == .btDraft)
                && $0.start >= week.now && $0.start < week.week.end
        }
        return week.weekMinutes + ahead.reduce(0) { $0 + $1.duration / 60 }
    }

    /// "7h 40m of 10h booked", or "No weekly goal".
    static func bookedLabel(_ project: Project, booked: Double) -> String {
        guard let goal = project.weeklyGoalHours else { return "No weekly goal" }
        return "\(CodeWeek.duration(minutes: booked)) of \(hours(goal)) booked"
    }

    static func make(for project: Project, week: CodeWeek, events: [CalendarEvent]) -> [CodeSuggestion] {
        let book = booking(for: project, week: week, booked: bookedMinutes(project, week: week, events: events))
        if project.stages.isEmpty {
            let draft = CodeSuggestion(title: "Draft a roadmap from the repo", label: "Draft", doneLabel: "Drafted ✓", action: .draftRoadmap)
            return [draft, book]
        }
        if project.weeklyGoalHours == nil {
            let h = defaultGoalHours
            return [book, CodeSuggestion(title: "Set a weekly goal for \(project.name)", label: "Set \(hours(h))",
                                         doneLabel: "Goal set ✓", action: .weeklyGoal(hours: h))]
        }
        guard let stage = CodeRoadmapLabels.current(in: project), let task = CodeRoadmapLabels.focusTask(in: stage) else {
            return [book]
        }
        return [book, CodeSuggestion(title: "Make “\(task.title)” a goal for this Focus session", label: "Set goal",
                                     doneLabel: "Goal set ✓", action: .focusGoal(task.title))]
    }

    /// Tomorrow at the project's best hour; the coming weekend morning with no history.
    static func booking(for project: Project, week: CodeWeek, booked: Double) -> CodeSuggestion {
        let cal = week.calendar
        let stage = CodeRoadmapLabels.current(in: project)
        let blockTitle = stage.map { "\(project.name) · \($0.name)" } ?? project.name
        guard let hour = week.bestStartHour else {
            let start = cal.nextDate(after: week.now, matching: DateComponents(hour: weekendHour, minute: 0, weekday: 7),
                                     matchingPolicy: .nextTime) ?? week.now
            return bookAction("Book 1h this weekend", start: start, hours: 1, title: blockTitle, calendar: cal)
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: week.now))!
        let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)!
        let gap = (project.weeklyGoalHours ?? 0) * 60 - booked
        let blockHours = gap > 0 ? min(maxBlockHours, max(1, Int((gap / 60).rounded(.up)))) : 1
        let what: String
        if gap > 0 {
            what = gap <= Double(blockHours * 60) ? "the rest" : "the \(hours(project.weeklyGoalHours ?? 0)) goal"
        } else {
            what = stage?.name.lowercased() ?? project.name
        }
        let day = weekday(start, calendar: cal)
        let range = CodeWeek.hourRange(hour, hour + blockHours, spaced: false)
        return bookAction("Book \(day) \(range) for \(what)", start: start, hours: blockHours, title: blockTitle, calendar: cal)
    }

    private static func bookAction(_ text: String, start: Date, hours: Int, title: String, calendar: Calendar) -> CodeSuggestion {
        let end = calendar.date(byAdding: .hour, value: hours, to: start)!
        return CodeSuggestion(title: text, label: "Add", doneLabel: "Added ✓", action: .book(start: start, end: end, title: title))
    }

    /// "10h", "2.5h".
    static func hours(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

extension AppStore {
    /// Performs a suggestion's write once and remembers it so the row shows its done label.
    func acceptCodeSuggestion(_ suggestion: CodeSuggestion, slot: Int, projectID: String) {
        guard code.accepted[projectID]?[slot] == nil, let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        switch suggestion.action {
        case let .book(start, end, title):
            let hours = Int(end.timeIntervalSince(start) / 3600)
            addEvent(CalendarEvent(
                title: title, start: start, end: end, kind: .studyPlanned, source: .bt,
                runAsFocus: true, focusPlan: "\(max(1, hours) * 2)×25", linkedProjectID: projectID
            ))
        case .focusGoal(let title):
            focus.goals.append(SessionGoal(title: title))
        case .weeklyGoal(let hours):
            projects[i].weeklyGoalHours = hours
        case .draftRoadmap:
            sendToBT("Draft a roadmap for \(projects[i].name) from the repo’s README and open issues.")
        }
        code.accepted[projectID, default: [:]][slot] = suggestion
    }

    /// Adds a placeholder project for a repo path and selects it. Returns false for a blank path.
    @discardableResult
    func trackRepo(path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.split(separator: "/").last.map(String.init) ?? ""
        guard !name.isEmpty, name != "~" else { return false }
        var id = name.lowercased()
        var n = 2
        while project(id) != nil {
            id = "\(name.lowercased())-\(n)"
            n += 1
        }
        projects.append(Project(id: id, name: name, path: trimmed, stack: "—"))
        selectedProjectID = id
        return true
    }
}
