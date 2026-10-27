import Foundation
import Testing
@testable import BTKit

@MainActor
struct CodeScreenActionsTests {
    let store = AppStore(clock: { AppStoreTests.thursday })

    func suggestions(_ id: String) -> [CodeSuggestion] {
        let p = store.project(id)!
        return CodeSuggestions.make(for: p, week: CodeWeek(activity: p.activity, now: store.now, calendar: store.calendar), events: store.events)
    }

    func date(_ day: Int, _ hour: Int) -> Date {
        Calendar.bt.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    // MARK: Roadmap labels

    @Test func stageLabels() {
        let bt = store.project("bt-client")!
        #expect(CodeRoadmapLabels.when(bt.stages[1], calendar: .bt) == "OCT 9 ✓")
        #expect(CodeRoadmapLabels.when(bt.stages[3], calendar: .bt) == "NOV")
        #expect(CodeRoadmapLabels.when(bt.stages[5], calendar: .bt) == "TBD")
        let current = CodeRoadmapLabels.current(in: bt)!
        #expect(current.index == 3)
        #expect(CodeRoadmapLabels.target(for: current, in: bt, now: store.now, calendar: .bt) == "Target Oct 30 · on track")
        #expect(CodeRoadmapLabels.focusTask(in: current)?.title == "Sync conflict UI")
        #expect(CodeRoadmapLabels.label(.inReview) == "IN REVIEW")
    }

    @Test func targetAtRiskOverdueAndMissing() {
        let tn = store.project("tariffninja")!
        let stage = CodeRoadmapLabels.current(in: tn)!
        #expect(CodeRoadmapLabels.target(for: stage, in: tn, now: store.now, calendar: .bt) == "Target Nov 6 · at risk")
        #expect(CodeRoadmapLabels.target(for: stage, in: tn, now: store.now.addingTimeInterval(30 * 86_400), calendar: .bt)
            == "Target Nov 6 · overdue")
        let mirai = store.project("mirai")!
        #expect(CodeRoadmapLabels.target(for: CodeRoadmapLabels.current(in: mirai)!, in: mirai, now: store.now, calendar: .bt)
            == "No target date yet")
    }

    // MARK: Suggestions

    @Test func bookedVersusGoal() {
        let p = store.project("bt-client")!
        let week = CodeWeek(activity: p.activity, now: store.now, calendar: store.calendar)
        let booked = CodeSuggestions.bookedMinutes(p, week: week, events: store.events)
        #expect(booked == 460) // 5h 40m logged + Friday's 2h block
        #expect(CodeSuggestions.bookedLabel(p, booked: booked) == "7h 40m of 10h booked")
        #expect(CodeSuggestions.bookedLabel(store.project("mirai")!, booked: 59) == "No weekly goal")
    }

    @Test func bookingAddsLinkedStudyBlockOnce() {
        let book = suggestions("bt-client")[0]
        #expect(book.title == "Book Fri 8–10 PM for the 10h goal")
        let before = store.events.count
        store.acceptCodeSuggestion(book, slot: 0, projectID: "bt-client")
        store.acceptCodeSuggestion(book, slot: 0, projectID: "bt-client")
        #expect(store.events.count == before + 1)
        let added = store.events.last!
        #expect(added.kind == .studyPlanned && added.linkedProjectID == "bt-client")
        #expect(added.start == date(23, 20) && added.end == date(23, 22))
        #expect(store.code.accepted["bt-client"]?[0]?.doneLabel == "Added ✓")
    }

    @Test func goalSuggestionAppendsFocusGoal() {
        let goal = suggestions("bt-client")[1]
        #expect(goal.action == .focusGoal("Sync conflict UI"))
        let count = store.focus.goals.count
        store.acceptCodeSuggestion(goal, slot: 1, projectID: "bt-client")
        #expect(store.focus.goals.count == count + 1)
        #expect(store.focus.goals.last?.title == "Sync conflict UI")
    }

    @Test func weeklyGoalSuggestionSetsGoal() {
        let s = suggestions("mirai")
        #expect(s[1].action == .weeklyGoal(hours: 3))
        #expect(s[1].label == "Set 3h")
        store.acceptCodeSuggestion(s[1], slot: 1, projectID: "mirai")
        #expect(store.project("mirai")?.weeklyGoalHours == 3)
        // The accepted row keeps its text even though fresh suggestions change.
        #expect(store.code.accepted["mirai"]?[1]?.title == "Set a weekly goal for mirai")
    }

    @Test func emptyProjectDraftsRoadmapAndBooksWeekend() {
        let s = suggestions("waypave")
        #expect(s.map(\.title) == ["Draft a roadmap from the README", "Book 1h this weekend"])
        #expect(s[1].action == .book(start: date(24, 10), end: date(24, 11), title: "waypave"))
        let threads = store.threads.count
        store.acceptCodeSuggestion(s[0], slot: 0, projectID: "waypave")
        #expect(store.threads.count == threads)
        #expect(store.code.accepted["waypave"]?[0] == nil)
    }

    @Test func trackRepoAddsAndSelectsPlaceholder() {
        #expect(!store.trackRepo(path: "   "))
        #expect(store.trackRepo(path: "~/dev/notes/"))
        #expect(store.trackRepo(path: "~/work/notes"))
        #expect(store.projects.suffix(2).map(\.id) == ["notes", "notes-2"])
        #expect(store.selectedProjectID == "notes-2")
        #expect(store.project("notes")?.stages.isEmpty == true)
    }
}
