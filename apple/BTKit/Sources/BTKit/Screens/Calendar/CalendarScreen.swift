import SwiftUI

/// Calendar: Week (default), Day and Month over the shared store.
/// Matches design/screens/CalWeek.dc.html, CalDay.dc.html and CalMonth.dc.html.
public struct CalendarScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            if store.calendarMode == .week {
                CalWeekToolbar(store: store)
            } else {
                CalToolbar(store: store)
                    .dashedEdges(right: false, bottom: true)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: Bindable(store.calendarScreen).eventEditor, onDismiss: { store.calCancelEditor() }) { draft in
            CalEventEditor(store: store, draft: draft)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.calendarMode {
        case .week:
            CalWeekGrid(store: store)
        case .day:
            HStack(spacing: 0) {
                CalDayAgenda(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let panel = store.calendarScreen.dayPanel {
                    ScrollView {
                        switch panel {
                        case .composer: CalDayComposer(store: store)
                        case .summary: CalDayGlance(store: store)
                        }
                    }
                    .frame(width: 340)
                    .dashedEdges(right: false, bottom: false, left: true)
                }
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
        Text(store.calendarStatus).lineLimit(1)
    }
}
