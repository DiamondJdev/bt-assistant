import Foundation

/// Every label the Focus screen shows, computed from the store at one moment.
struct FocusSummary {
    /// Minutes before the next event you should leave.
    static let leadMinutes = 10
    static let tickCount = 24

    let session: ActiveFocusSession
    let now: Date
    let calendar: Calendar
    let next: CalendarEvent?
    let focusedSeconds: Int
    let goalSeconds: Int

    @MainActor init(_ store: AppStore) {
        self.init(
            session: store.focus, now: store.now, calendar: store.calendar, next: store.nextEventToday,
            focusedSeconds: store.focusedTodaySeconds, goalSeconds: store.focusGoalSeconds
        )
    }

    init(session: ActiveFocusSession, now: Date, calendar: Calendar, next: CalendarEvent?, focusedSeconds: Int, goalSeconds: Int) {
        self.session = session
        self.now = now
        self.calendar = calendar
        self.next = next
        self.focusedSeconds = focusedSeconds
        self.goalSeconds = goalSeconds
    }

    var isBreak: Bool { session.mode == .break }

    // MARK: Hard stop

    var hardStopMinutes: Int? {
        next.map { max(0, Int($0.start.timeIntervalSince(now)) / 60) }
    }

    /// "MATH 26103 · Discrete Math" → "Discrete Math".
    var nextShortTitle: String? {
        next.map { $0.title.components(separatedBy: " · ").last ?? $0.title }
    }

    var leaveBy: Date? {
        next.map { $0.start.addingTimeInterval(-Double(Self.leadMinutes * 60)) }
    }

    /// "Leave by 1:20 · [Room]"
    var leaveByLine: String? {
        guard let leaveBy else { return nil }
        let base = "Leave by \(time(leaveBy))"
        guard let room = next?.location, !room.isEmpty else { return base }
        return "\(base) · \(room)"
    }

    // MARK: Ring

    var sessionLabel: String {
        isBreak ? "Break · \(ActiveFocusSession.breakLength / 60) min" : "Session \(session.number) of \(session.plannedCount)"
    }

    var taskLabel: String { isBreak ? "Stand up, water, no phone" : session.taskTitle }

    /// "Break at 1:07" while focusing, "Session 3 next" during a break.
    var nextStepLabel: String {
        isBreak
            ? "Session \(session.number + 1) next"
            : "Break at \(time(now.addingTimeInterval(Double(session.remainingSeconds))))"
    }

    /// "Class at 1:30"
    var nextEventLabel: String {
        guard let next else { return "Nothing else today" }
        let name = next.kind == .classSession ? "Class" : (nextShortTitle ?? next.title)
        return "\(name) at \(time(next.start))"
    }

    var ofLabel: String {
        if session.remainingSeconds == 0 { return isBreak ? "Break over" : "Session complete" }
        let total = "of \(ActiveFocusSession.clock(session.plannedSeconds))"
        return session.isPaused ? "Paused · \(total)" : total
    }

    /// `ofLabel` turns accentText when paused or finished.
    var ofIsAlert: Bool { session.isPaused || session.remainingSeconds == 0 }

    var pauseLabel: String { session.isPaused ? "Resume" : "Pause" }
    var endLabel: String { isBreak ? "Start session \(session.number + 1)" : "End session" }

    // MARK: Goals and totals

    var goalsDone: Int { session.goals.filter(\.isDone).count }
    var goalsLabel: String { "\(goalsDone) of \(session.goals.count) done" }

    var focusedMinutes: Int { focusedSeconds / 60 }
    var focusedLabel: String { "\(focusedMinutes / 60)h \(focusedMinutes % 60)m" }
    var goalLabel: String { "Goal \(goalSeconds / 3600)h" }

    var focusedTicks: Int {
        guard goalSeconds > 0 else { return 0 }
        let ticks = (Double(focusedSeconds) / Double(goalSeconds) * Double(Self.tickCount)).rounded()
        return min(Self.tickCount, Int(ticks))
    }

    // MARK: BT note

    /// The plain and accent halves of the one-line BT note.
    var btNote: (plain: String, accent: String) {
        let leave = leaveBy.map(time)
        switch (isBreak, leave) {
        case let (false, leave?): return ("At the break I’ll fade the music and", "remind you to leave by \(leave).")
        case (false, nil): return ("At the break I’ll fade the music.", "Nothing else is on today.")
        case let (true, leave?): return ("Music is paused for your break.", "Leave for class by \(leave).")
        case (true, nil): return ("Music is paused for your break.", "Stand up and stretch.")
        }
    }

    // MARK: Formatting

    /// "1:07" — 12-hour, no meridiem, in the store's calendar.
    func time(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = (c.hour ?? 0) % 12
        return String(format: "%d:%02d", hour == 0 ? 12 : hour, c.minute ?? 0)
    }
}
