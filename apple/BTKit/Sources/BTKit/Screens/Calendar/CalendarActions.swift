import Foundation

/// Calendar screen actions on the shared store. UI-only bits live on `calendarScreen`.
extension AppStore {
    // MARK: Navigation

    func calStep(_ n: Int) {
        calendarDate = CalDates.step(calendarDate, mode: calendarMode, by: n, calendar)
        selectedEventID = nil
    }

    func calGoToday() {
        calendarDate = now
    }

    func calSelect(_ id: String?) {
        selectedEventID = selectedEventID == id ? nil : id
    }

    // MARK: Editing

    /// Moves a block by whole minutes, keeping its length.
    func calNudge(_ id: String, minutes: Int) {
        guard var e = event(id) else { return }
        e.start = e.start.addingTimeInterval(Double(minutes * 60))
        e.end = e.end.addingTimeInterval(Double(minutes * 60))
        updateEvent(e)
    }

    func calSetTitle(_ id: String, _ title: String) {
        guard var e = event(id), e.title != title else { return }
        e.title = title
        updateEvent(e)
    }

    func calSetRunAsFocus(_ id: String, _ on: Bool) {
        guard var e = event(id) else { return }
        e.runAsFocus = on
        if on, e.focusPlan == nil { e.focusPlan = "50/10" }
        updateEvent(e)
    }

    /// First free hour-long slot from the next whole hour, 8 AM–10 PM, over the coming week.
    func calNextFreeSlot(after date: Date, length: TimeInterval = 3600) -> Date? {
        let startHour = Int(CalTimeline.startHour), endHour = Int(CalTimeline.endHour)
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else { continue }
            for h in startHour..<endHour {
                guard let slot = calendar.date(bySettingHour: h, minute: 0, second: 0, of: day), slot >= date,
                      slot.addingTimeInterval(length) <= calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day)!
                else { continue }
                let end = slot.addingTimeInterval(length)
                let clash = events.contains { $0.kind != .deadline && $0.start < end && $0.end > slot }
                if !clash { return slot }
            }
        }
        return nil
    }

    /// "+ New event": a study block at the next free hour, opened for editing.
    @discardableResult
    func calNewEvent() -> CalendarEvent {
        let start = calNextFreeSlot(after: now) ?? calendar.date(byAdding: .hour, value: 1, to: now)!
        let event = CalendarEvent(
            title: "New event", start: start, end: start.addingTimeInterval(3600),
            kind: .studyPlanned, source: .bt, runAsFocus: true, focusPlan: "50/10"
        )
        addEvent(event)
        if calendarMode == .month { calendarMode = .week }
        calendarDate = start
        selectedEventID = event.id
        return event
    }

    // MARK: Week BT bar

    var calDraftEvent: CalendarEvent? { event(CalDraftReview.draftID) }

    func calKeepDraft() {
        calResolveDraft(.kept) { e in
            e.kind = .studyPlanned
            e.runAsFocus = true
            if e.focusPlan == nil { e.focusPlan = "2×25" }
        }
    }

    func calMoveDraftLater() {
        calResolveDraft(.moved) { e in
            e.start = e.start.addingTimeInterval(3600)
            e.end = e.end.addingTimeInterval(3600)
        }
    }

    func calDiscardDraft() {
        guard let e = calDraftEvent else { return }
        calendarScreen.draft = CalDraftReview(outcome: .discarded, before: e)
        deleteEvent(e.id)
    }

    /// Puts the draft back as it was before Keep / Move / Discard.
    func calUndoDraft() {
        if let before = calendarScreen.draft.before {
            if event(before.id) != nil { updateEvent(before) } else { addEvent(before) }
        }
        calendarScreen.draft = CalDraftReview()
    }

    private func calResolveDraft(_ outcome: CalDraftReview.Outcome, _ change: (inout CalendarEvent) -> Void) {
        guard let before = calDraftEvent else { return }
        var e = before
        change(&e)
        updateEvent(e)
        calendarScreen.draft = CalDraftReview(outcome: outcome, before: before)
    }

    // MARK: Day

    /// Inserts BT's drafted block; `edit` opens it inline.
    func calAddDayDraft(_ draft: CalDayDraft, edit: Bool = false) {
        let e = CalendarEvent(
            title: draft.title, start: draft.start, end: draft.end, kind: .studyPlanned, source: .bt,
            runAsFocus: true, focusPlan: draft.focusPlan
        )
        addEvent(e)
        calendarScreen.dayDraft = draft
        calendarScreen.dayDraftAddedID = e.id
        if edit { selectedEventID = e.id }
    }

    func calUndoDayDraft() {
        if let id = calendarScreen.dayDraftAddedID { deleteEvent(id) }
        calendarScreen.dayDraftAddedID = nil
    }

    /// "+ Fill with study": an hour-long study block at the start of the gap, opened inline.
    func calFillGap(at start: Date) {
        let e = CalendarEvent(
            title: "Study block", start: start, end: start.addingTimeInterval(3600),
            kind: .studyPlanned, source: .bt, runAsFocus: true, focusPlan: "2×25"
        )
        addEvent(e)
        selectedEventID = e.id
    }

    // MARK: Month look-ahead

    /// Drafts BT blocks into next week and turns the Study layer on.
    func calDraftLookAhead() {
        guard calendarScreen.monthDraftIDs.isEmpty else { return }
        let drafts = CalMonthMath.lookAheadDrafts(now: now, cal: calendar)
        drafts.forEach(addEvent)
        calendarScreen.monthDraftIDs = drafts.map(\.id)
        calendarScreen.monthLayers.insert(.study)
    }

    func calUndoLookAhead() {
        calendarScreen.monthDraftIDs.forEach { deleteEvent($0) }
        calendarScreen.monthDraftIDs = []
    }
}
