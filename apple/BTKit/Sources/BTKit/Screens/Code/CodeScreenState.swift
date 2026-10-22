import Foundation
import Observation

/// UI state that only the Code screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class CodeScreenState {
    /// Weekly goal for all projects together (the "All projects" tick bar).
    public var allProjectsGoalHours: Double = 12
    /// Accepted suggestions by project id, then row. Stored whole so the row keeps its text.
    public var accepted: [String: [Int: CodeSuggestion]] = [:]
    /// The "+ Track a repo" path field, while open.
    public var trackDraft: String?

    public init() {}
}
