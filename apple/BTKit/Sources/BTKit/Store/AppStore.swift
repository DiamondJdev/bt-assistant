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
    public var calendarDate: Date {
        didSet { reloadEventsIfNeeded() }
    }
    public var selectedEventID: String?
    public var selectedProjectID: String?
    public var selectedThreadID: String?

    // MARK: Shared data

    /// Timed events. All-day ones live in `allDayEvents` so they never count as busy time.
    public var events: [CalendarEvent]
    public var allDayEvents: [CalendarEvent]
    public var focus: ActiveFocusSession {
        didSet { savePlans() }
    }
    public var focusedTodaySeconds: Int
    public var focusGoalSeconds = 2 * 3600
    public var doNotDisturb = true
    public var projects: [Project] {
        didSet { savePlans() }
    }
    /// Projects removed from Code. Heartbeat reloads skip them until the repo is tracked again.
    public var hiddenProjectIDs: Set<String> {
        didSet { savePlans() }
    }
    public var memories: [Memory]
    public var todos: [TodoItem]
    public var threads: [ChatThread]
    /// Newest first.
    public var ledger: [LedgerEntry]
    public let nowPlaying: (any NowPlayingSource)?
    /// The BT server connection. BT shows sample threads while it has no address.
    public let chat: ChatModel?
    /// EventKit. Without one, `events` are sample data kept in memory.
    public let calendarSource: (any CalendarSource)?
    /// The last calendar write that failed, until the next successful reload.
    public private(set) var calendarError: String?
    public private(set) var calendarSyncedAt: Date?
    /// The real timer the menu bar shares. Without one, `focus` is a sample session counted down here.
    public let pomodoro: PomodoroModule?
    /// VS Code sessions. Without one, `projects` are sample data.
    public let codeSource: (any CodeActivitySource)?

    // MARK: Per-screen state

    public let today = TodayState()
    public let focusScreen = FocusScreenState()
    public let calendarScreen: CalendarScreenState
    public let code = CodeScreenState()
    public let btScreen = BTScreenState()

    private let clock: () -> Date
    private var loadedWindow: DateInterval?
    private var loadedTokens: [Int]?
    var loadedCode: (token: Int, day: Date)?
    /// Where `SavedPlans` live. Nil in tests and previews, which keep everything in memory.
    private let savedPlans: UserDefaults?
    private var lastSavedPlans: SavedPlans?

    public init(
        clock: @escaping () -> Date = { .now },
        calendar: Calendar = .bt,
        sample: SampleData? = nil,
        nowPlaying: (any NowPlayingSource)? = nil,
        chat: ChatModel? = nil,
        calendarSource: (any CalendarSource)? = nil,
        pomodoro: PomodoroModule? = nil,
        codeSource: (any CodeActivitySource)? = nil,
        savedPlans: UserDefaults? = nil
    ) {
        let start = clock()
        let sample = sample ?? SampleData(now: start, calendar: calendar)
        self.clock = clock
        self.now = start
        self.calendar = calendar
        self.calendarDate = start
        let saved = savedPlans.flatMap(SavedPlans.load)
        self.savedPlans = savedPlans
        self.lastSavedPlans = saved
        self.calendarScreen = CalendarScreenState(defaults: savedPlans)
        self.events = calendarSource == nil ? sample.events : []
        self.allDayEvents = calendarSource == nil ? sample.allDayEvents : []
        self.focus = pomodoro == nil ? sample.focus : ActiveFocusSession(
            taskTitle: saved?.focus.taskTitle ?? "Focus", projectID: saved?.focus.projectID,
            goals: saved?.focus.goals ?? [], startedAt: start
        )
        self.focusedTodaySeconds = pomodoro == nil ? sample.focusedTodaySeconds : 0
        self.projects = codeSource == nil ? sample.projects : saved?.savedProjects ?? []
        self.hiddenProjectIDs = Set(saved?.hiddenProjectIDs ?? [])
        self.memories = sample.memories
        self.todos = sample.todos
        self.threads = sample.threads
        self.ledger = sample.ledger
        self.nowPlaying = nowPlaying
        self.chat = chat
        self.calendarSource = calendarSource
        self.pomodoro = pomodoro
        self.codeSource = codeSource
        if let pomodoro, let title = saved?.focus.taskTitle { pomodoro.label = title }
        self.selectedThreadID = sample.threads.first?.id
        syncFocus()
        reloadEventsIfNeeded()
        reloadProjectsIfNeeded()
        self.selectedProjectID = projects.first?.id
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
                calSelect(eventID)
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
        if let pomodoro {
            pomodoro.tick()
            syncFocus()
            reloadEventsIfNeeded()
            reloadProjectsIfNeeded()
            return
        }
        reloadEventsIfNeeded()
        reloadProjectsIfNeeded()
        guard !focus.isPaused, focus.remainingSeconds > 0 else { return }
        focus.remainingSeconds -= 1
        if focus.mode == .focus {
            focusedTodaySeconds += 1
            if focus.remainingSeconds == 0 { endFocusSegment() }
        }
    }

    // MARK: Focus

    public func toggleFocusPause() {
        guard let pomodoro else { return focus.isPaused.toggle() }
        if pomodoro.state.isRunning { pomodoro.pause() } else { pomodoro.start() }
        syncFocus()
    }

    /// +5 min adds 300s to both the time left and the total.
    public func addFiveMinutes() {
        guard let pomodoro else {
            focus.remainingSeconds += 300
            focus.plannedSeconds += 300
            return
        }
        pomodoro.extend(by: 300)
        syncFocus()
    }

    /// "End session" in focus mode, "Start session N" from a break.
    public func endOrStartNext() {
        if let pomodoro {
            pomodoro.skip()
            pomodoro.start()
            syncFocus()
            reloadEventsIfNeeded()
            return
        }
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
        if let pomodoro {
            pomodoro.label = event.title
            pomodoro.startWork(length: Double(minutes * 60))
            syncFocus()
        }
        route = .focus
    }

    /// "Add a goal" on Focus. Ignores blank text.
    public func addFocusGoal(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        focus.goals.append(SessionGoal(title: trimmed))
    }

    /// Writes `SavedPlans` when the hand-set parts changed; the timer ticking alone writes nothing.
    private func savePlans() {
        guard let savedPlans else { return }
        let plans = SavedPlans(focus: focus, projects: projects, hiddenProjectIDs: hiddenProjectIDs)
        guard plans != lastSavedPlans else { return }
        plans.save(to: savedPlans)
        lastSavedPlans = plans
    }

    /// Copies the Pomodoro timer into `focus`, keeping the task, project and goals.
    private func syncFocus() {
        guard let pomodoro else { return }
        let state = pomodoro.state
        let active = state.isRunning || state.isPaused
        let planned = active ? state.phaseDuration : pomodoro.durations.duration(of: state.phase)
        let remaining = pomodoro.remaining() ?? planned
        let done = state.completedWorkPhases
        focus.mode = state.phase == .work ? .focus : .break
        focus.plannedSeconds = Int(planned)
        focus.remainingSeconds = Int(remaining.rounded(.up))
        focus.isPaused = !state.isRunning
        focus.number = state.phase == .work ? done + 1 : max(1, done)
        focus.plannedCount = max(pomodoro.durations.longBreakEvery, focus.number)
        focus.startedAt = state.startedAt ?? now
        let running = state.phase == .work ? planned - remaining : 0
        // ponytail: reads the focus log every tick; cache per day if it shows up in profiles.
        focusedTodaySeconds = Int(pomodoro.todayFocused + running)
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

    /// All-day events covering any part of `day`, multi-day ones on each day they span.
    public func allDayEvents(on day: Date) -> [CalendarEvent] {
        guard let d = calendar.dateInterval(of: .day, for: day) else { return [] }
        return allDayEvents.filter { $0.start < d.end && $0.end > d.start }.sorted { $0.title < $1.title }
    }

    @discardableResult
    public func addEvent(_ event: CalendarEvent) -> CalendarEvent? {
        guard let saved = written(event) else { return nil }
        events.append(saved)
        return saved
    }

    @discardableResult
    public func updateEvent(_ event: CalendarEvent) -> CalendarEvent? {
        guard let i = events.firstIndex(where: { $0.id == event.id }), let saved = written(event) else { return nil }
        events[i] = saved
        if selectedEventID == event.id { selectedEventID = saved.id }
        return saved
    }

    @discardableResult
    public func deleteEvent(_ id: String) -> CalendarEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return nil }
        if let calendarSource, !Self.localKinds.contains(events[i].kind) {
            do {
                try calendarSource.delete(events[i])
            } catch {
                return calendarWriteFailed(error)
            }
        }
        if selectedEventID == id { selectedEventID = nil }
        return events.remove(at: i)
    }

    /// Drafts and logged focus never go to EventKit; they live in memory.
    static let localKinds: Set<EventKind> = [.btDraft, .focusLogged]

    /// The event as the source stored it, or nil when the write failed.
    private func written(_ event: CalendarEvent) -> CalendarEvent? {
        guard let calendarSource, !Self.localKinds.contains(event.kind) else { return event }
        do {
            return try calendarSource.save(event)
        } catch {
            return calendarWriteFailed(error)
        }
    }

    private func calendarWriteFailed(_ error: any Error) -> CalendarEvent? {
        calendarError = "Calendar couldn’t save: \(error.localizedDescription)"
        loadedTokens = nil
        reloadEventsIfNeeded()
        return nil
    }

    /// Re-reads EventKit when it changed or the window no longer covers now and the shown date.
    /// ponytail: six weeks either side; a bigger jump reloads on the next tick.
    func reloadEventsIfNeeded() {
        guard calendarSource != nil || pomodoro != nil else { return }
        let tokens = [calendarSource?.changeToken ?? 0, pomodoro?.logToken ?? 0]
        if tokens == loadedTokens, let window = loadedWindow, window.contains(now), window.contains(calendarDate) { return }
        let margin: TimeInterval = 42 * 24 * 3600
        let window = DateInterval(start: min(now, calendarDate) - margin, end: max(now, calendarDate) + margin)
        let fetched = calendarSource?.events(in: window)
        let shared = fetched?.filter { !$0.isAllDay } ?? events.filter { !Self.localKinds.contains($0.kind) }
        if let fetched { allDayEvents = fetched.filter(\.isAllDay) }
        let focusLog = pomodoro.map { loggedFocusEvents($0, in: window) } ?? events.filter { $0.kind == .focusLogged }
        events = shared + events.filter { $0.kind == .btDraft } + focusLog
        if tokens.first != loadedTokens?.first, loadedTokens != nil { calendarError = nil }
        loadedTokens = tokens
        loadedWindow = window
        calendarSyncedAt = now
        if let id = selectedEventID, event(id) == nil { selectedEventID = nil }
    }

    private func loggedFocusEvents(_ pomodoro: PomodoroModule, in window: DateInterval) -> [CalendarEvent] {
        pomodoro.loggedSessions(in: window).map { interval, label in
            CalendarEvent(
                id: "focus-\(interval.start.timeIntervalSince1970)", title: label ?? "Focus",
                start: interval.start, end: interval.end, kind: .focusLogged, source: .focus,
                focusPlan: "\(Int(interval.end.timeIntervalSince(interval.start)) / 60) min"
            )
        }
    }

    /// The Calendar header: where events come from and when they last synced.
    public var calendarStatus: String {
        guard let calendarSource else { return "Sample data" }
        if let calendarError { return calendarError }
        guard calendarSource.hasAccess else { return "Calendar access is off" }
        return "Calendar — synced " + (calendarSyncedAt.map { BTFormat.clock($0, calendar) } ?? "never")
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

    /// Re-reads coding activity when it changed or the day rolled over. Goals, roadmaps and
    /// tracked repos live here, so they carry over. ponytail: in memory only; lost on relaunch.
    func reloadProjectsIfNeeded() {
        guard let codeSource else { return }
        let day = calendar.startOfDay(for: now)
        if let loadedCode, loadedCode.token == codeSource.changeToken, loadedCode.day == day { return }
        // Five weeks covers this week plus the three-week average.
        let since = calendar.date(byAdding: .day, value: -35, to: day) ?? day
        let focusBlocks = events.filter { $0.kind == .focusLogged }
        let fresh = codeSource.projects(since: since).filter { !hiddenProjectIDs.contains($0.id) }.map { p in
            var p = p
            if let old = project(p.id) {
                p.name = old.name
                p.weeklyGoalHours = old.weeklyGoalHours
                p.stages = old.stages
                p.branch = old.branch
                p.bookmark = old.bookmark
                if !old.path.isEmpty { p.path = old.path }
            }
            p.activity = p.activity.map { run in
                var run = run
                run.insideFocusSessionID = focusBlocks.first { $0.start < run.end && run.start < $0.end }?.id
                return run
            }
            return p
        }
        let ids = Set(fresh.map(\.id))
        projects = fresh + projects.filter { !ids.contains($0.id) }
        loadedCode = (codeSource.changeToken, day)
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

    /// Posts a user message to BT and lets BT answer. Returns the local thread used,
    /// or nil when the message went to the server as a new conversation.
    @discardableResult
    public func sendToBT(_ text: String, threadID: String? = nil) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let chat, btIsLive {
            guard !trimmed.isEmpty else { return nil }
            chat.startNewConversation()
            chat.draft = trimmed
            Task { await chat.send() }
            return nil
        }
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
