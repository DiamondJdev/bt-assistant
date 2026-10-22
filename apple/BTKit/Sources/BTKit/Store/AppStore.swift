import Foundation
import Observation

/// The one store every screen reads. A block booked on Today shows up in Calendar, Focus and BT.
/// Screen-only UI state lives in the per-screen state objects (`today`, `focusScreen`, ...).
@MainActor
@Observable
public final class AppStore {
    // MARK: Clock and navigation

    public private(set) var now: Date
    public var calendar: Calendar
    public var route: AppRoute = .today
    public var calendarMode: CalendarMode = .week
    /// The day Calendar Day/Week/Month is showing.
    public var calendarDate: Date
    public var selectedEventID: String?
    public var selectedProjectID: String?
    public var selectedThreadID: String?

    // MARK: Shared data

    public var events: [CalendarEvent]
    public var focus: ActiveFocusSession
    public var focusedTodaySeconds: Int
    public var focusGoalSeconds = 2 * 3600
    public var doNotDisturb = true
    public var projects: [Project]
    public var memories: [Memory]
    public var todos: [TodoItem]
    public var threads: [ChatThread]
    /// Newest first.
    public var ledger: [LedgerEntry]
    public let nowPlaying: (any NowPlayingSource)?

    // MARK: Per-screen state

    public let today = TodayState()
    public let focusScreen = FocusScreenState()
    public let calendarScreen = CalendarScreenState()
    public let code = CodeScreenState()
    public let btScreen = BTScreenState()

    private let clock: () -> Date

    public init(
        clock: @escaping () -> Date = { .now },
        calendar: Calendar = .bt,
        sample: SampleData? = nil,
        nowPlaying: (any NowPlayingSource)? = nil
    ) {
        let start = clock()
        let sample = sample ?? SampleData(now: start, calendar: calendar)
        self.clock = clock
        self.now = start
        self.calendar = calendar
        self.calendarDate = start
        self.events = sample.events
        self.focus = sample.focus
        self.focusedTodaySeconds = sample.focusedTodaySeconds
        self.projects = sample.projects
        self.memories = sample.memories
        self.todos = sample.todos
        self.threads = sample.threads
        self.ledger = sample.ledger
        self.nowPlaying = nowPlaying
        self.selectedProjectID = sample.projects.first?.id
        self.selectedThreadID = sample.threads.first?.id
    }

    // MARK: Navigation

    public func open(_ link: DeepLink) {
        switch link {
        case .today:
            route = .today
        case .focus:
            route = .focus
        case let .calendar(mode, date, eventID):
            calendarMode = mode
            if let date { calendarDate = date }
            if let eventID {
                selectedEventID = eventID
                if let event = event(eventID) { calendarDate = event.start }
            }
            route = .calendar
        case let .code(projectID):
            if let projectID { selectedProjectID = projectID }
            route = .code
        case let .bt(threadID, projectID):
            if let threadID {
                selectedThreadID = threadID
            } else if let projectID {
                selectedThreadID = thread(forProject: projectID)
            }
            route = .bt
        }
    }

    // MARK: Clock

    /// Called once a second by the app shell.
    public func tick() {
        now = clock()
        guard !focus.isPaused, focus.remainingSeconds > 0 else { return }
        focus.remainingSeconds -= 1
        if focus.mode == .focus {
            focusedTodaySeconds += 1
            if focus.remainingSeconds == 0 { endFocusSegment() }
        }
    }

    // MARK: Focus

    public func toggleFocusPause() {
        focus.isPaused.toggle()
    }

    /// +5 min adds 300s to both the time left and the total.
    public func addFiveMinutes() {
        focus.remainingSeconds += 300
        focus.plannedSeconds += 300
    }

    /// "End session" in focus mode, "Start session N" from a break.
    public func endOrStartNext() {
        switch focus.mode {
        case .focus: endFocusSegment()
        case .break: startNextSession()
        }
    }

    /// Starts focus from a calendar block, pre-filled with its task and plan.
    public func startFocus(from event: CalendarEvent) {
        let minutes = event.focusPlan.flatMap(Self.sessionMinutes) ?? ActiveFocusSession.focusLength / 60
        focus = ActiveFocusSession(
            taskTitle: event.title, projectID: event.linkedProjectID, number: 1,
            plannedCount: max(1, Int(event.duration) / (minutes * 60)),
            plannedSeconds: minutes * 60, startedAt: now
        )
        route = .focus
    }

    /// Writes the focus time so far to Calendar and switches to a break.
    private func endFocusSegment() {
        let worked = focus.plannedSeconds - focus.remainingSeconds
        if worked >= 60 {
            events.append(CalendarEvent(
                title: focus.taskTitle,
                start: now.addingTimeInterval(-Double(worked)), end: now,
                kind: .focusLogged, source: .focus,
                focusPlan: "\(worked / 60) min", linkedProjectID: focus.projectID
            ))
        }
        focus.mode = .break
        focus.plannedSeconds = ActiveFocusSession.breakLength
        focus.remainingSeconds = ActiveFocusSession.breakLength
        focus.isPaused = false
    }

    private func startNextSession() {
        focus.mode = .focus
        focus.number += 1
        focus.plannedSeconds = ActiveFocusSession.focusLength
        focus.remainingSeconds = ActiveFocusSession.focusLength
        focus.isPaused = false
        focus.startedAt = now
    }

    /// "50/10" → 50, "2×25" → 25.
    static func sessionMinutes(_ plan: String) -> Int? {
        let parts = plan.split(whereSeparator: { $0 == "/" || $0 == "×" || $0 == "x" })
        guard parts.count == 2 else { return nil }
        return plan.contains("/") ? Int(parts[0]) : Int(parts[1])
    }

    // MARK: Calendar

    public func event(_ id: String) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    public func events(on day: Date) -> [CalendarEvent] {
        events.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }

    public func addEvent(_ event: CalendarEvent) {
        events.append(event)
    }

    public func updateEvent(_ event: CalendarEvent) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i] = event
    }

    @discardableResult
    public func deleteEvent(_ id: String) -> CalendarEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return nil }
        if selectedEventID == id { selectedEventID = nil }
        return events.remove(at: i)
    }

    /// The next event that starts after now today (for "hard stop").
    public var nextEventToday: CalendarEvent? {
        events(on: now).first { $0.start > now && $0.kind != .deadline && $0.kind != .focusLogged }
    }

    // MARK: Projects

    public func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: BT

    public func thread(_ id: String?) -> ChatThread? {
        guard let id else { return nil }
        return threads.first { $0.id == id }
    }

    private func thread(forProject projectID: String) -> String {
        if let existing = threads.first(where: { $0.projectID == projectID }) { return existing.id }
        let name = project(projectID)?.name ?? "project"
        let new = ChatThread(title: "About \(name)", projectID: projectID)
        threads.insert(new, at: 0)
        return new.id
    }

    /// Posts a user message to BT and lets BT answer. Returns the thread used.
    @discardableResult
    public func sendToBT(_ text: String, threadID: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if let threadID, thread(threadID) != nil {
            id = threadID
        } else {
            let new = ChatThread(title: String(trimmed.prefix(40)))
            threads.insert(new, at: 0)
            id = new.id
        }
        guard !trimmed.isEmpty, let i = threads.firstIndex(where: { $0.id == id }) else { return id }
        threads[i].messages.append(Message(role: .user, text: trimmed, time: now))
        respond(to: trimmed, in: id)
        return id
    }

    /// Records a BT write in the ledger. Every BT action also puts a `ResultCard` in its thread.
    public func record(_ entry: LedgerEntry) {
        ledger.insert(entry, at: 0)
    }

    /// Reverses a BT write in its module and marks the thread card undone.
    public func undo(_ entryID: String) {
        guard let i = ledger.firstIndex(where: { $0.id == entryID }), !ledger[i].isUndone else { return }
        switch ledger[i].undo {
        case .removeEvent(let id):
            deleteEvent(id)
        case .restoreEvent(let event):
            if self.event(event.id) != nil { updateEvent(event) } else { addEvent(event) }
        case .removeMemory(let id):
            memories.removeAll { $0.id == id }
        case .removeTodo(let id):
            todos.removeAll { $0.id == id }
        case let .restoreStage(projectID, stage):
            if let p = projects.firstIndex(where: { $0.id == projectID }),
               let s = projects[p].stages.firstIndex(where: { $0.id == stage.id }) {
                projects[p].stages[s] = stage
            }
        }
        ledger[i].isUndone = true
        if let cardID = ledger[i].resultCardID { markCardUndone(cardID) }
    }

    private func markCardUndone(_ cardID: String) {
        for t in threads.indices {
            for m in threads[t].messages.indices {
                if let c = threads[t].messages[m].resultCards.firstIndex(where: { $0.id == cardID }) {
                    threads[t].messages[m].resultCards[c].isUndone = true
                    return
                }
            }
        }
    }
}

public extension Calendar {
    /// Gregorian, weeks start Monday.
    static var bt: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }
}
