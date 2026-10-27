import Foundation

/// What a message asks BT to do. Keyword routing from the prototype's `reply()`.
enum BTIntent: Equatable {
    case memory, todo, calendar, status, insight, fallback

    static func route(_ text: String) -> BTIntent {
        let low = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { low.contains($0) } }
        if has("remember") { return .memory }
        if has("todo", "to-do") || low.hasPrefix("add ") { return .todo }
        if has("block", "book", "schedule", "move") { return .calendar }
        if has("status", "mark", "merged", "shipped") { return .status }
        if has("@code", "code", "project", "focus", "how", "?") { return .insight }
        return .fallback
    }

    /// The thing to write: "remember the lab is in room 210" → "The lab is in room 210".
    static func body(_ text: String) -> String {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(#/^/(remember|todo|block|status)\s*/#.ignoresCase(), with: "")
            .replacing(#/^(please\s+)?(remember( that)?|add( a)?( to-?do)?( to)?|mark|block|book|schedule)\s+/#.ignoresCase(), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
        guard let first = stripped.first else { return "New item" }
        return first.uppercased() + stripped.dropFirst()
    }
}

extension AppStore {
    /// BT's answer to a user message already appended to `threadID`.
    /// The prototype routes by keyword; the real app will use BT's tool calls.
    func respond(to text: String, in threadID: String) {
        let projectID = thread(threadID)?.projectID
        let body = BTIntent.body(text)
        switch BTIntent.route(text) {
        case .memory: saveMemory(body, threadID: threadID, projectID: projectID)
        case .todo: addTodo(body, threadID: threadID, projectID: projectID)
        case .calendar: bookStudyBlock(body, threadID: threadID, projectID: projectID)
        case .status: updateStatus(text, threadID: threadID, projectID: projectID)
        case .insight: reply(Message(role: .bt, insight: codingInsight(projectID: projectID), time: now), in: threadID)
        case .fallback:
            reply(Message(role: .bt, text: "Got it. I can block time, answer questions about any module, remember things, add to-dos, or update a status. Try a shortcut below.", time: now), in: threadID)
        }
    }

    // MARK: Writes. Each one adds a card to the thread and an entry to the ledger.

    private func saveMemory(_ body: String, threadID: String, projectID: String?) {
        let memory = Memory(text: body, tag: project(projectID)?.name.uppercased() ?? "FROM CHAT", createdAt: now, sourceThreadID: threadID)
        memories.append(memory)
        let card = ResultCard(kind: .memory, verb: .saved, title: body, detail: "From this chat")
        write(card, text: "Saved. I’ll bring it up when it’s relevant.", summary: body, undo: .removeMemory(id: memory.id), in: threadID)
    }

    private func addTodo(_ body: String, threadID: String, projectID: String?) {
        let todo = TodoItem(title: body, projectID: projectID)
        todos.append(todo)
        let detail = ["Today", project(projectID)?.name ?? "no due time"].joined(separator: " · ")
        let card = ResultCard(kind: .todo, verb: .added, title: body, detail: detail)
        write(card, text: "Added to your list.", summary: body, undo: .removeTodo(id: todo.id), in: threadID)
    }

    private func bookStudyBlock(_ body: String, threadID: String, projectID: String?) {
        let start = nextEveningSlot()
        let event = CalendarEvent(
            title: body, start: start, end: start.addingTimeInterval(3600), kind: .studyPlanned, source: .bt,
            runAsFocus: true, focusPlan: "2×25", linkedProjectID: projectID
        )
        addEvent(event)
        let day = BTFormat.weekday(start, calendar)
        let card = ResultCard(
            kind: .calendar, verb: .added, title: body,
            detail: "\(day) \(BTFormat.clock(start, calendar)) – \(BTFormat.clock(event.end, calendar)) · Study",
            deepLink: .calendar(.week, eventID: event.id)
        )
        write(card, text: "Booked the next open slot tonight. Focus will run it as 2 × 25.",
              summary: "\(body) · \(day) \(BTFormat.clock(start, calendar))", undo: .removeEvent(id: event.id), in: threadID)
    }

    /// Marks the roadmap task named in `text` in its project's current stage.
    private func updateStatus(_ text: String, threadID: String, projectID: String?) {
        let low = text.lowercased()
        let scope = projects.indices.filter { projectID == nil || projects[$0].id == projectID }
        for p in scope {
            guard let s = projects[p].stages.firstIndex(where: { $0.status == .current }),
                  let t = projects[p].stages[s].tasks.firstIndex(where: { low.contains($0.title.lowercased()) })
            else { continue }
            let previous = projects[p].stages[s]
            let reviewing = low.contains("review")
            let open = previous.tasks.filter { $0.status != .done }.count
            var stage = previous
            stage.tasks[t].status = reviewing ? .inReview : .done
            if !reviewing, previous.tasks[t].status != .done, open > 0 {
                stage.progress = previous.progress + (1 - previous.progress) / Double(open)
            }
            projects[p].stages[s] = stage
            let label = reviewing ? "In review" : (low.contains("merged") ? "Merged" : "Done")
            let card = ResultCard(
                kind: .status, verb: .updated, title: "\(stage.tasks[t].title) → \(label)",
                detail: "Stage \(stage.index): \(BTFormat.percent(previous.progress)) → \(BTFormat.percent(stage.progress))",
                deepLink: .code(projectID: projects[p].id)
            )
            write(card, text: "Updated.", summary: card.title,
                  undo: .restoreStage(projectID: projects[p].id, stage: previous), in: threadID)
            return
        }
        reply(Message(role: .bt, text: "I couldn’t find that task on a current roadmap stage.", time: now), in: threadID)
    }

    private func write(_ card: ResultCard, text: String, summary: String, undo: UndoToken, in threadID: String) {
        reply(Message(role: .bt, text: text, resultCards: [card], time: now), in: threadID)
        record(LedgerEntry(time: now, kind: card.kind, summary: summary, undo: undo, resultCardID: card.id))
    }

    private func reply(_ message: Message, in threadID: String) {
        guard let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[i].messages.append(message)
    }

    // MARK: Reads

    /// Today's coding total from project activity, scoped to one project when set.
    func codingInsight(projectID: String?) -> Insight {
        let scoped = projects.filter { projectID == nil || $0.id == projectID }
        let today = scoped.flatMap(\.activity).filter { calendar.isDate($0.start, inSameDayAs: now) }
        let total = today.reduce(0) { $0 + $1.duration }
        let inFocus = today.filter { $0.insideFocusSessionID != nil }.reduce(0) { $0 + $1.duration }
        let share = total > 0 ? inFocus / total : 0
        if let project = scoped.first, projectID != nil {
            let stage = project.stages.first { $0.status == .current }
            let waiting = stage?.tasks.filter { $0.status == .needsYou }.count ?? 0
            let stageText = stage.map { "Stage \($0.index) (\($0.name)) is \(BTFormat.percent($0.progress)) done. " } ?? ""
            let waitText = waiting == 0 ? "Nothing is waiting on you." : "\(waiting) task\(waiting == 1 ? " is" : "s are") waiting on you."
            return Insight(value: BTFormat.duration(total), sentence: "Coded on \(project.name) today. " + stageText + waitText,
                           link: .code(projectID: project.id))
        }
        let count = Set(today.map(\.projectID)).count
        return Insight(
            value: BTFormat.duration(total),
            sentence: "Coded today across \(count) project\(count == 1 ? "" : "s"), \(BTFormat.percent(share)) of it inside Focus.",
            link: .code(projectID: nil)
        )
    }

    /// First free hour from 7 PM in 30-minute steps; tomorrow 7 PM when tonight is full.
    func nextEveningSlot() -> Date {
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        let busy = events(on: now).filter { $0.kind != .deadline }
        for step in 0...4 {
            let start = evening.addingTimeInterval(Double(step) * 1800)
            let end = start.addingTimeInterval(3600)
            if start >= now, !busy.contains(where: { $0.start < end && start < $0.end }) { return start }
        }
        return calendar.date(byAdding: .day, value: 1, to: evening) ?? evening
    }
}

/// Small text helpers for BT. Non-mutating, locale-free.
enum BTFormat {
    /// "1:05"
    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = (c.hour ?? 0) % 12 == 0 ? 12 : (c.hour ?? 0) % 12
        return String(format: "%d:%02d", hour, c.minute ?? 0)
    }

    /// "1:05 PM"
    static func clockWithPeriod(_ date: Date, _ calendar: Calendar) -> String {
        clock(date, calendar) + ((calendar.component(.hour, from: date) < 12) ? " AM" : " PM")
    }

    /// "Thu"
    static func weekday(_ date: Date, _ calendar: Calendar) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][calendar.component(.weekday, from: date) - 1]
    }

    /// "3h 12m", "45m"
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "70%"
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
