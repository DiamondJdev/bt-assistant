import SwiftUI

/// Placeholder. Build to match design/screens/BT.dc.html.
public struct BTScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("BT").interStyle(40, .medium, tracking: -0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Column 4 of the header while BT is open.
public struct BTHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View { EmptyView() }
}
