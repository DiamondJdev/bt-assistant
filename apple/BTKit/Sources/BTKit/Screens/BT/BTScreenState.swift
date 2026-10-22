import Observation

/// UI state that only the BT screen uses. Shared data belongs on `AppStore`.
@MainActor
@Observable
public final class BTScreenState {
    public init() {}
}
