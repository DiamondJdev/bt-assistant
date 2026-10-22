import SwiftUI

/// Placeholder. Build to match design/screens/Today.dc.html.
public struct TodayScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("Today").interStyle(40, .medium, tracking: -0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Column 4 of the header while Today is open.
public struct TodayHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View { EmptyView() }
}
