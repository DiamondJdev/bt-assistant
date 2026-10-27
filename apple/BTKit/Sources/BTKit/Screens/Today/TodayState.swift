import Observation

/// UI state that only the Today screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class TodayState {
    /// The study block "Book 2:55" added, and the ledger entry that undoes it.
    public var bookedEventID: String?
    public var bookedLedgerID: String?
    /// Composer text and the last message sent from it.
    public var draft = ""
    public var sentText: String?
    public var sentThreadID: String?

    public init() {}
}
