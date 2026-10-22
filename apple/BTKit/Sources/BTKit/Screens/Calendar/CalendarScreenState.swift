import Foundation
import Observation

/// UI state that only the Calendar screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class CalendarScreenState {
    // Week
    var hiddenWeekLayers: Set<CalWeekLayer> = []
    var draft = CalDraftReview()

    // Day
    var nlInput = CalDayDraft.defaultPrompt
    /// Set by Send; nil shows the draft parsed from the default prompt.
    var dayDraft: CalDayDraft?
    var dayDraftAddedID: String?

    // Month
    var monthLayers: Set<CalMonthLayer> = [.study, .due, .classes]
    var monthDraftIDs: [String] = []

    public init() {}
}

/// Week sidebar calendar layers. Toggling one hides its kinds.
enum CalWeekLayer: String, CaseIterable, Hashable {
    case classes, study, focus, due, work

    var name: String {
        switch self {
        case .classes: "UARK classes"
        case .study: "Study blocks"
        case .focus: "Focus logged"
        case .due: "Blackboard due dates"
        case .work: "Work"
        }
    }

    var source: String {
        switch self {
        case .classes: "APPLE"
        case .study: "BT"
        case .focus: "FOCUS"
        case .due, .work: "GOOGLE"
        }
    }

    var kinds: Set<EventKind> {
        switch self {
        case .classes: [.classSession]
        case .study: [.studyPlanned, .btDraft]
        case .focus: [.focusLogged]
        case .due: [.deadline]
        case .work: [.work]
        }
    }

    /// Swatch style matches the block it stands for.
    var swatchKind: EventKind {
        switch self {
        case .classes: .classSession
        case .study: .studyPlanned
        case .focus: .focusLogged
        case .due: .deadline
        case .work: .work
        }
    }
}

/// Month toolbar layer pills. Work is off by default.
enum CalMonthLayer: String, CaseIterable, Hashable {
    case study, due, classes, work

    var name: String {
        switch self {
        case .study: "Study"
        case .due: "Due"
        case .classes: "Class"
        case .work: "Work"
        }
    }

    var kinds: Set<EventKind> {
        switch self {
        case .study: [.studyPlanned, .btDraft, .focusLogged]
        case .due: [.deadline]
        case .classes: [.classSession]
        case .work: [.work]
        }
    }
}

enum CalLayers {
    /// Kinds left visible after hiding the given week layers.
    static func visible(_ events: [CalendarEvent], hiding hidden: Set<CalWeekLayer>) -> [CalendarEvent] {
        let off = hidden.reduce(into: Set<EventKind>()) { $0.formUnion($1.kinds) }
        return events.filter { !off.contains($0.kind) }
    }

    static func visible(_ events: [CalendarEvent], showing layers: Set<CalMonthLayer>) -> [CalendarEvent] {
        let on = layers.reduce(into: Set<EventKind>()) { $0.formUnion($1.kinds) }
        return events.filter { on.contains($0.kind) }
    }
}

/// The Week BT bar's proposal about the sample draft block, with the block as it was for Undo.
struct CalDraftReview: Equatable {
    enum Outcome: Equatable { case pending, kept, moved, discarded }

    static let draftID = "draft"

    var outcome: Outcome = .pending
    var before: CalendarEvent?
}
