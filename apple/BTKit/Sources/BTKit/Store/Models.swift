import Foundation

// Shared data model from design/HANDOFF.md. Plain values; `AppStore` owns them.

public enum EventKind: String, CaseIterable, Sendable {
    case classSession, work, focusLogged, studyPlanned, btDraft, deadline
}

public enum EventSource: String, Sendable {
    case apple, google, bt, focus, blackboard
}

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var kind: EventKind
    public var source: EventSource
    public var location: String?
    public var runAsFocus: Bool
    /// e.g. "2×25" or "50/10".
    public var focusPlan: String?
    public var linkedProjectID: String?
    public var linkedAssignmentID: String?
    /// Shown in the all-day row; `AppStore` keeps these in `allDayEvents`, apart from timed `events`.
    public var isAllDay: Bool
    public var calendarTitle: String?
    public var hasAttendees: Bool
    public var recurrenceSummary: String?

    public init(
        id: String = UUID().uuidString, title: String, start: Date, end: Date, kind: EventKind, source: EventSource,
        location: String? = nil, runAsFocus: Bool = false, focusPlan: String? = nil,
        linkedProjectID: String? = nil, linkedAssignmentID: String? = nil, isAllDay: Bool = false,
        calendarTitle: String? = nil, hasAttendees: Bool = false, recurrenceSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
        self.location = location
        self.runAsFocus = runAsFocus
        self.focusPlan = focusPlan
        self.linkedProjectID = linkedProjectID
        self.linkedAssignmentID = linkedAssignmentID
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.hasAttendees = hasAttendees
        self.recurrenceSummary = recurrenceSummary
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum FocusMode: String, Sendable { case focus, `break` }

public struct SessionGoal: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var title: String
    public var isDone: Bool

    public init(id: String = UUID().uuidString, title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct ActiveFocusSession: Equatable, Sendable {
    public static let focusLength = 1500
    public static let breakLength = 300

    public var id: String
    public var taskTitle: String
    public var projectID: String?
    /// 1-based number of this session in today's set, and the planned count.
    public var number: Int
    public var plannedCount: Int
    public var plannedSeconds: Int
    public var remainingSeconds: Int
    public var mode: FocusMode
    public var isPaused: Bool
    public var goals: [SessionGoal]
    public var startedAt: Date

    public init(
        id: String = UUID().uuidString, taskTitle: String, projectID: String? = nil, number: Int = 1, plannedCount: Int = 4,
        plannedSeconds: Int = ActiveFocusSession.focusLength, remainingSeconds: Int? = nil, mode: FocusMode = .focus,
        isPaused: Bool = false, goals: [SessionGoal] = [], startedAt: Date = .now
    ) {
        self.id = id
        self.taskTitle = taskTitle
        self.projectID = projectID
        self.number = number
        self.plannedCount = plannedCount
        self.plannedSeconds = plannedSeconds
        self.remainingSeconds = remainingSeconds ?? plannedSeconds
        self.mode = mode
        self.isPaused = isPaused
        self.goals = goals
        self.startedAt = startedAt
    }

    /// 0…1, for the LineRing.
    public var progress: Double {
        plannedSeconds > 0 ? 1 - Double(remainingSeconds) / Double(plannedSeconds) : 0
    }

    /// "18:42"
    public var clock: String { Self.clock(remainingSeconds) }

    public static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

public enum StageStatus: String, Codable, Sendable { case done, current, next, final }
public enum RoadmapTaskStatus: String, Codable, Sendable { case done, inReview, inProgress, todo, needsYou }
public enum ActivitySource: String, Codable, Sendable { case agent, review, manual }

public struct RoadmapTask: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var title: String
    public var status: RoadmapTaskStatus

    public init(id: String = UUID().uuidString, title: String, status: RoadmapTaskStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

public struct RoadmapStage: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var index: Int
    public var name: String
    public var status: StageStatus
    public var targetDate: Date?
    public var completedDate: Date?
    public var progress: Double
    public var tasks: [RoadmapTask]

    public init(
        id: String = UUID().uuidString, index: Int, name: String, status: StageStatus, targetDate: Date? = nil,
        completedDate: Date? = nil, progress: Double = 0, tasks: [RoadmapTask] = []
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.status = status
        self.targetDate = targetDate
        self.completedDate = completedDate
        self.progress = progress
        self.tasks = tasks
    }
}

public struct CodingActivity: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var projectID: String
    public var insideFocusSessionID: String?
    public var source: ActivitySource

    public init(start: Date, end: Date, projectID: String, insideFocusSessionID: String? = nil, source: ActivitySource) {
        self.start = start
        self.end = end
        self.projectID = projectID
        self.insideFocusSessionID = insideFocusSessionID
        self.source = source
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct Project: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var stack: String
    public var branch: String?
    public var weeklyGoalHours: Double?
    public var stages: [RoadmapStage]
    public var activity: [CodingActivity]
    /// Security-scoped bookmark for the repo folder picked in Code, so the sandboxed app can read its README.
    public var bookmark: Data?

    public init(
        id: String, name: String, path: String, stack: String, branch: String? = nil, weeklyGoalHours: Double? = nil,
        stages: [RoadmapStage] = [], activity: [CodingActivity] = [], bookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.stack = stack
        self.branch = branch
        self.weeklyGoalHours = weeklyGoalHours
        self.stages = stages
        self.activity = activity
        self.bookmark = bookmark
    }
}

public struct Memory: Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var tag: String
    public var createdAt: Date
    public var sourceThreadID: String?

    public init(id: String = UUID().uuidString, text: String, tag: String, createdAt: Date = .now, sourceThreadID: String? = nil) {
        self.id = id
        self.text = text
        self.tag = tag
        self.createdAt = createdAt
        self.sourceThreadID = sourceThreadID
    }
}

public struct TodoItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var due: Date?
    public var projectID: String?
    public var isDone: Bool

    public init(id: String = UUID().uuidString, title: String, due: Date? = nil, projectID: String? = nil, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.due = due
        self.projectID = projectID
        self.isDone = isDone
    }
}

public enum MessageRole: String, Sendable { case user, bt }

public struct Insight: Equatable, Sendable {
    public var value: String
    public var sentence: String
    public var link: DeepLink?

    public init(value: String, sentence: String, link: DeepLink? = nil) {
        self.value = value
        self.sentence = sentence
        self.link = link
    }
}

public enum ResultKind: String, Sendable { case calendar, memory, todo, status }
public enum ResultVerb: String, Sendable { case moved, added, saved, updated }

public struct ResultCard: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ResultKind
    public var verb: ResultVerb
    public var title: String
    public var detail: String
    public var deepLink: DeepLink?
    public var isUndone: Bool

    public init(
        id: String = UUID().uuidString, kind: ResultKind, verb: ResultVerb, title: String, detail: String,
        deepLink: DeepLink? = nil, isUndone: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.verb = verb
        self.title = title
        self.detail = detail
        self.deepLink = deepLink
        self.isUndone = isUndone
    }
}

public struct Message: Identifiable, Equatable, Sendable {
    public var id: String
    public var role: MessageRole
    public var text: String?
    public var insight: Insight?
    public var resultCards: [ResultCard]
    public var time: Date
    /// Display name of the provider that answered ("OpenAI", "Ollama"), if the server said.
    public var provider: String?

    public init(
        id: String = UUID().uuidString, role: MessageRole, text: String? = nil, insight: Insight? = nil,
        resultCards: [ResultCard] = [], time: Date = .now, provider: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.role = role
        self.text = text
        self.insight = insight
        self.resultCards = resultCards
        self.time = time
    }
}

public struct ChatThread: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var messages: [Message]
    /// Set when a thread was opened from "Ask about <project>".
    public var projectID: String?

    public init(id: String = UUID().uuidString, title: String, messages: [Message] = [], projectID: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.projectID = projectID
    }
}

/// How to reverse one BT write. Applied by `AppStore.undo(_:)`.
public enum UndoToken: Equatable, Sendable {
    case removeEvent(id: String)
    case restoreEvent(CalendarEvent)
    case removeMemory(id: String)
    case removeTodo(id: String)
    case restoreStage(projectID: String, stage: RoadmapStage)
}

public struct LedgerEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var time: Date
    public var kind: ResultKind
    public var summary: String
    public var undo: UndoToken
    /// The thread card this write produced, so Undo can mark it.
    public var resultCardID: String?
    public var isUndone: Bool

    public init(
        id: String = UUID().uuidString, time: Date = .now, kind: ResultKind, summary: String, undo: UndoToken,
        resultCardID: String? = nil, isUndone: Bool = false
    ) {
        self.id = id
        self.time = time
        self.kind = kind
        self.summary = summary
        self.undo = undo
        self.resultCardID = resultCardID
        self.isUndone = isUndone
    }
}

// MARK: - Navigation

public enum AppRoute: String, CaseIterable, Sendable {
    case today, focus, code, calendar, bt

    public var title: String {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .code: "Code"
        case .calendar: "Calendar"
        case .bt: "BT"
        }
    }
}

public enum CalendarMode: String, CaseIterable, Sendable { case day, week, month }

/// A cross-module link target. Result cards and links carry one.
public enum DeepLink: Equatable, Sendable {
    case today
    case focus
    case calendar(CalendarMode, date: Date? = nil, eventID: String? = nil)
    case code(projectID: String?)
    case bt(threadID: String? = nil, projectID: String? = nil)
}
