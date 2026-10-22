import SwiftUI

/// Calendar: Week (default), Day and Month over the shared store.
/// Matches design/screens/CalWeek.dc.html, CalDay.dc.html and CalMonth.dc.html.
public struct CalendarScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            CalToolbar(store: store)
                .dashedEdges(right: false, bottom: true)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.calendarMode {
        case .week:
            SandGrid(columns: 4, rows: [1]) {
                CalWeekSidebar(store: store)
                    .dashedEdges(right: true, bottom: false)
                    .gridCell(0, 0)
                CalWeekGrid(store: store)
                    .gridCell(1, 0, columns: 3)
            }
        case .day:
            SandGrid(columns: 4, rows: [1]) {
                CalDayAgenda(store: store)
                    .dashedEdges(right: true, bottom: false)
                    .gridCell(0, 0, columns: 2)
                CalDayComposer(store: store)
                    .dashedEdges(right: true, bottom: false)
                    .gridCell(2, 0)
                CalDayGlance(store: store)
                    .gridCell(3, 0)
            }
        case .month:
            SandGrid(columns: 4, rows: [1]) {
                CalMonthGrid(store: store)
                    .dashedEdges(right: true, bottom: false)
                    .gridCell(0, 0, columns: 3)
                CalMonthPanel(store: store)
                    .gridCell(3, 0)
            }
        }
    }
}

/// Column 4 of the header while Calendar is open.
public struct CalendarHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text("Apple · Google — synced 1m ago")
    }
}
