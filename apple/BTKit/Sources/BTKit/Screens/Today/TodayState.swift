import Observation

/// UI state that only the Today screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class TodayState {
    public init() {}
}
