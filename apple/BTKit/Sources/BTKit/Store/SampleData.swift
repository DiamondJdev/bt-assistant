import Foundation

/// Sample data matching design/screens, anchored to the current week so "today" is always real.
/// Swap for real sources through `CalendarSource` and `CodeActivitySource` later.
public struct SampleData {
    public var events: [CalendarEvent]
    public var focus: ActiveFocusSession
    public var focusedTodaySeconds: Int
    public var projects: [Project]
    public var memories: [Memory]
    public var todos: [TodoItem]
    public var threads: [ChatThread]
    public var ledger: [LedgerEntry]

    public init(now: Date = .now, calendar: Calendar = .bt) {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let todayIndex = calendar.dateComponents([.day], from: week, to: calendar.startOfDay(for: now)).day ?? 3
        let at = { (day: Int, hour: Double) -> Date in
            calendar.date(byAdding: .minute, value: Int(((Double(day * 24) + hour) * 60).rounded()), to: week)!
        }
        events = Self.weekEvents(at: at, todayIndex: todayIndex)
        focus = ActiveFocusSession(
            id: "focus-now", taskTitle: "Calendar sync module", projectID: "bt-client", number: 2, plannedCount: 4,
            plannedSeconds: 1500, remainingSeconds: 1122,
            goals: [
                SessionGoal(id: "g1", title: "Write EventKit adapter", isDone: true),
                SessionGoal(id: "g2", title: "Unit tests for recurring events"),
                SessionGoal(id: "g3", title: "Push to bt-client"),
            ],
            startedAt: now.addingTimeInterval(-378)
        )
        focusedTodaySeconds = 31 * 60
        projects = Self.projects(at: at, todayIndex: todayIndex)
        memories = SampleData.btMemories(now: now)
        todos = SampleData.btTodos(now: now)
        threads = SampleData.btThreads(now: now)
        ledger = SampleData.btLedger(now: now)
    }

    /// The week from CalWeek.dc.html. Index 3 (Thursday) in the mockup is "today"; here today is real.
    private static func weekEvents(at: (Int, Double) -> Date, todayIndex t: Int) -> [CalendarEvent] {
        func e(_ id: String, _ title: String, _ day: Int, _ a: Double, _ b: Double, _ kind: EventKind,
               _ source: EventSource, room: String? = nil, plan: String? = nil, project: String? = nil) -> CalendarEvent {
            CalendarEvent(
                id: id, title: title, start: at(day, a), end: at(day, b), kind: kind, source: source, location: room,
                runAsFocus: kind == .studyPlanned || kind == .btDraft, focusPlan: plan, linkedProjectID: project
            )
        }
        // Days other than today keep the mockup's weekday; today's schedule moves to the real day.
        func d(_ mockDay: Int) -> Int { mockDay == 3 ? t : (mockDay == t ? 3 : mockDay) }
        return [
            e("m1", "GEOL 11103", d(0), 9.5, 10.75, .classSession, .apple, room: "[Room]"),
            e("m2", "CHEM 14103", d(0), 11, 12.25, .classSession, .apple, room: "[Room]"),
            e("m3", "bt-client", d(0), 14, 15.67, .focusLogged, .focus, plan: "4×25", project: "bt-client"),
            e("t1", "HIST 20103", d(1), 11, 12.25, .classSession, .apple, room: "[Room]"),
            e("t2", "MATH 26103 · Discrete Math", d(1), 13.5, 14.75, .classSession, .apple, room: "[Room]"),
            e("t3", "Discrete HW", d(1), 19, 20.5, .focusLogged, .focus, plan: "3×25"),
            e("w1", "Work", d(2), 8, 12, .work, .google),
            e("w2", "McMillion", d(2), 15.25, 16.5, .classSession, .apple, room: "[Room]"),
            e("h1", "GEOL 11103", d(3), 9.5, 10.75, .classSession, .apple, room: "[Room]"),
            e("h2", "HIST 20103", d(3), 11, 12.25, .classSession, .apple, room: "[Room]"),
            e("h4", "MATH 26103 · Discrete Math", d(3), 13.5, 14.75, .classSession, .apple, room: "[Room]"),
            e("hw6", "Discrete HW 6 — problems 4–8", d(3), 14.92, 15.75, .studyPlanned, .bt, plan: "2×25"),
            e("h5", "CHEM 14103 · SI session", d(3), 16, 17, .classSession, .apple, room: "[Room]"),
            e("draft", "CHEM review", d(3), 17.5, 18.5, .btDraft, .bt, plan: "2×25"),
            e("due-hw6", "Discrete Math HW 6", d(3), 23 + 59.0 / 60, 23 + 59.0 / 60, .deadline, .blackboard),
            e("f1", "HIST 20103", d(4), 11, 12.25, .classSession, .apple, room: "[Room]"),
            e("f2", "bt-client deep work", d(4), 13, 15, .studyPlanned, .bt, plan: "50/10", project: "bt-client"),
            e("due-lab", "CHEM lab report", d(4), 23 + 59.0 / 60, 23 + 59.0 / 60, .deadline, .blackboard),
            e("s1", "Work shift", d(5), 10, 18, .work, .google),
            e("u1", "Work shift", d(6), 9, 17, .work, .google),
            e("u2", "HIST reading", d(6), 19, 20, .studyPlanned, .bt, plan: "2×25"),
            e("due-hist", "HIST response", d(6), 23 + 59.0 / 60, 23 + 59.0 / 60, .deadline, .blackboard),
        ]
    }

    /// Projects from Code.dc.html. Activity hours per weekday follow each project's 7-day spark;
    /// today's hours follow Today's code-time line (bt-client 1h48 · tariffninja 52m · mirai 32m).
    private static func projects(at: (Int, Double) -> Date, todayIndex t: Int) -> [Project] {
        func activity(_ id: String, _ hoursByDay: [Double], todayHours: Double) -> [CodingActivity] {
            var hours = hoursByDay
            for i in hours.indices where i > t { hours[i] = 0 }
            if t < hours.count { hours[t] = todayHours }
            return hours.enumerated().compactMap { day, h in
                guard h > 0 else { return nil }
                let start = at(day, day == t ? 10 : 20)
                return CodingActivity(
                    start: start, end: start.addingTimeInterval(h * 3600), projectID: id,
                    insideFocusSessionID: day == t ? "focus-now" : nil, source: .agent
                )
            }
        }
        func stage(_ i: Int, _ name: String, _ status: StageStatus, progress: Double = 0, tasks: [RoadmapTask] = []) -> RoadmapStage {
            RoadmapStage(id: "s\(i)", index: i, name: name, status: status, progress: progress, tasks: tasks)
        }
        return [
            Project(
                id: "bt-client", name: "bt-client", path: "~/dev/bt-client", stack: "Swift", branch: "main", weeklyGoalHours: 10,
                stages: [
                    stage(1, "BT chat client", .done, progress: 1),
                    stage(2, "Focus + Pomodoro", .done, progress: 1),
                    stage(3, "Calendar sync", .current, progress: 0.7, tasks: [
                        RoadmapTask(id: "t1", title: "EventKit adapter", status: .done),
                        RoadmapTask(id: "t2", title: "Focus writes to calendar", status: .done),
                        RoadmapTask(id: "t3", title: "DST recurrence", status: .inReview),
                        RoadmapTask(id: "t4", title: "Sync conflict UI", status: .needsYou),
                    ]),
                    stage(4, "Code Time module", .next),
                    stage(5, "iOS client", .next),
                    stage(6, "BT OS v1.0", .final),
                ],
                activity: activity("bt-client", [1.6, 0.3, 0.4, 2.6, 0, 0, 0], todayHours: 1.8)
            ),
            Project(
                id: "tariffninja", name: "tariffninja", path: "~/work/tariffninja", stack: "TypeScript", branch: "develop", weeklyGoalHours: 4,
                stages: [
                    stage(1, "PSC filing engine", .done, progress: 1),
                    stage(2, "Refund tracker", .done, progress: 1),
                    stage(3, "PSC batch export", .current, progress: 0.45, tasks: [
                        RoadmapTask(id: "t1", title: "CSV schema", status: .done),
                        RoadmapTask(id: "t2", title: "Batch validation", status: .inReview),
                        RoadmapTask(id: "t3", title: "ACE upload format", status: .needsYou),
                    ]),
                    stage(4, "Broker portal", .next),
                    stage(5, "[Next milestone]", .final),
                ],
                activity: activity("tariffninja", [1, 0.6, 0.3, 0, 0, 0, 0], todayHours: 52.0 / 60)
            ),
            Project(
                id: "mirai", name: "mirai", path: "~/dev/mirai", stack: "TypeScript", branch: "main",
                stages: [
                    stage(1, "Counselor chat", .done, progress: 1),
                    stage(2, "Essay feedback", .current, progress: 0.3, tasks: [
                        RoadmapTask(id: "t1", title: "Rubric prompts", status: .done),
                        RoadmapTask(id: "t2", title: "Inline comments", status: .inProgress),
                        RoadmapTask(id: "t3", title: "Reviewer QA", status: .todo),
                    ]),
                    stage(3, "Pricing + paywall", .next),
                    stage(4, "Public launch", .final),
                ],
                activity: activity("mirai", [0.2, 0, 0.2, 0.6, 0, 0, 0], todayHours: 32.0 / 60)
            ),
            Project(id: "waypave", name: "waypave", path: "~/work/waypave", stack: "Python"),
        ]
    }
}
