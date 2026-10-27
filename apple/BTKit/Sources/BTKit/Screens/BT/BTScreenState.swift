import Observation

/// UI state that only the BT screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class BTScreenState {
    /// The composer text.
    public var draft = ""
    /// "See all" in BT remembers.
    public var showAllMemories = false

    public init() {}
}
