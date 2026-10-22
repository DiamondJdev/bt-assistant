import SwiftUI

/// Placeholder. Build to match design/screens/Code.dc.html.
public struct CodeScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("Code").interStyle(40, .medium, tracking: -0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Column 4 of the header while Code is open.
public struct CodeHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View { EmptyView() }
}
