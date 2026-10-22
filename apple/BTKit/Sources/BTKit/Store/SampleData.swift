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
        projects = Self.projects(at: at, todayIndex: todayIndex, now: now)
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

    /// Projects from Code.dc.html. Activity is agent runs and reviews, mostly in the evening;
    /// today's totals follow Today's code-time line (bt-client 1h48 · tariffninja 52m · mirai 32m).
    /// Days are relative to this week's Monday; past days after today are dropped.
    private static func projects(at: (Int, Double) -> Date, todayIndex t: Int, now: Date) -> [Project] {
        func run(_ id: String, _ day: Int, _ hour: Double, _ minutes: Double, focus: String? = nil,
                 _ source: ActivitySource = .agent) -> CodingActivity {
            let start = at(day, hour)
            return CodingActivity(start: start, end: start.addingTimeInterval(minutes * 60), projectID: id,
                                  insideFocusSessionID: focus, source: source)
        }
        /// Mockup weekdays before today, plus today's runs and three earlier weeks.
        func week(_ past: [CodingActivity], today: [CodingActivity], earlier: [CodingActivity]) -> [CodingActivity] {
            let todayStart = at(t, 0)
            return earlier + past.filter { $0.start < todayStart } + today
        }
        func stage(_ i: Int, _ name: String, _ status: StageStatus, done: Int? = nil, target: Int? = nil,
                   progress: Double = 0, tasks: [RoadmapTask] = []) -> RoadmapStage {
            RoadmapStage(id: "s\(i)", index: i, name: name, status: status, targetDate: target.map { at($0, 12) },
                         completedDate: done.map { at($0, 12) }, progress: progress, tasks: tasks)
        }
        // bt-client's last run ends now, so it reads "Coding now".
        let btLatest = max(now.addingTimeInterval(-48 * 60), at(t, 10.1))
        let bt = "bt-client", tn = "tariffninja", mi = "mirai"
        return [
            Project(
                id: bt, name: "bt-client", path: "~/dev/bt-client", stack: "Swift", branch: "main", weeklyGoalHours: 10,
                stages: [
                    stage(1, "BT chat client", .done, done: -31, progress: 1),
                    stage(2, "Focus + Pomodoro", .done, done: -10, progress: 1),
                    stage(3, "Calendar sync", .current, target: 11, progress: 0.7, tasks: [
                        RoadmapTask(id: "t1", title: "EventKit adapter", status: .done),
                        RoadmapTask(id: "t2", title: "Focus writes to calendar", status: .done),
                        RoadmapTask(id: "t3", title: "DST recurrence", status: .inReview),
                        RoadmapTask(id: "t4", title: "Sync conflict UI", status: .needsYou),
                    ]),
                    stage(4, "Code Time module", .next, target: 30),
                    stage(5, "iOS client", .next, target: 50),
                    stage(6, "BT OS v1.0", .final),
                ],
                activity: week(
                    [
                        run(bt, 0, 14, 45, focus: "f-mon"), run(bt, 0, 14.75, 45, focus: "f-mon", .review),
                        run(bt, 0, 20, 30), run(bt, 0, 20.5, 20, .review), run(bt, 0, 20.92, 20),
                        run(bt, 1, 21, 20), run(bt, 1, 21.34, 10, .review),
                        run(bt, 2, 22, 20), run(bt, 2, 22.34, 22, .review),
                    ],
                    today: [
                        run(bt, t, 9, 45, focus: "focus-am"), run(bt, t, 9.75, 15, focus: "focus-am", .review),
                        CodingActivity(start: btLatest, end: btLatest.addingTimeInterval(48 * 60), projectID: bt,
                                       insideFocusSessionID: "focus-now", source: .agent),
                    ],
                    earlier: [run(bt, -6, 14, 149), run(bt, -13, 14, 300), run(bt, -20, 14, 280)]
                )
            ),
            Project(
                id: tn, name: "tariffninja", path: "~/work/tariffninja", stack: "TypeScript", branch: "develop", weeklyGoalHours: 4,
                stages: [
                    stage(1, "PSC filing engine", .done, done: -91, progress: 1),
                    stage(2, "Refund tracker", .done, done: -24, progress: 1),
                    stage(3, "PSC batch export", .current, target: 18, progress: 0.45, tasks: [
                        RoadmapTask(id: "t1", title: "CSV schema", status: .done),
                        RoadmapTask(id: "t2", title: "Batch validation", status: .inReview),
                        RoadmapTask(id: "t3", title: "ACE upload format", status: .needsYou),
                    ]),
                    stage(4, "Broker portal", .next, target: 35),
                    stage(5, "[Next milestone]", .final),
                ],
                activity: week(
                    [run(tn, 0, 9.17, 40, focus: "f-tn"), run(tn, 1, 9.5, 20, .review)],
                    today: [run(tn, t, 10.08, 20), run(tn, t, 10.5, 15, .review), run(tn, t, 10.75, 17)],
                    earlier: [run(tn, -6, 9, 190), run(tn, -13, 9, 180), run(tn, -20, 9, 200)]
                )
            ),
            Project(
                id: mi, name: "mirai", path: "~/dev/mirai", stack: "TypeScript", branch: "main",
                stages: [
                    stage(1, "Counselor chat", .done, done: -59, progress: 1),
                    stage(2, "Essay feedback", .current, progress: 0.3, tasks: [
                        RoadmapTask(id: "t1", title: "Rubric prompts", status: .done),
                        RoadmapTask(id: "t2", title: "Inline comments", status: .inProgress),
                        RoadmapTask(id: "t3", title: "Reviewer QA", status: .todo),
                    ]),
                    stage(3, "Pricing + paywall", .next),
                    stage(4, "Public launch", .final),
                ],
                activity: week(
                    [run(mi, 0, 19.17, 12), run(mi, 2, 19, 15, .review)],
                    today: [run(mi, t, 11.33, 32, focus: "f-mirai")],
                    earlier: [run(mi, -6, 19, 60), run(mi, -13, 19, 55), run(mi, -20, 19, 65)]
                )
            ),
            Project(
                id: "waypave", name: "waypave", path: "~/work/waypave", stack: "Python",
                activity: [run("waypave", t - 9, 15, 40)]
            ),
        ]
    }
}
