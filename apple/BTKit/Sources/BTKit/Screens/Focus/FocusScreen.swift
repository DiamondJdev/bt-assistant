import SwiftUI

/// Placeholder. Build to match design/screens/Focus.dc.html.
public struct FocusScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("Focus").interStyle(40, .medium, tracking: -0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Column 4 of the header while Focus is open.
public struct FocusHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View { EmptyView() }
}
