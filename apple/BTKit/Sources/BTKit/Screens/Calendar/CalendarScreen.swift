import SwiftUI

/// Placeholder. Build to match design/screens/CalWeek.dc.html, CalDay.dc.html and CalMonth.dc.html.
public struct CalendarScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("Calendar").interStyle(40, .medium, tracking: -0.045)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Column 4 of the header while Calendar is open.
public struct CalendarHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View { EmptyView() }
}
