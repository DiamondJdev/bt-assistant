import SwiftUI

/// Today: clock, agenda, code time · focus ring, BT statement · greeting, composer.
public struct TodayScreen: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        SandGrid(columns: 4, rows: [1, 1.25, 0.95], minRowHeights: [220, 280, 200]) {
            TodayClockCell(store: store).gridCell(0, 0)
            TodayAgendaCell(store: store).gridCell(1, 0, columns: 2)
            TodayCodeTimeCell(store: store).gridCell(3, 0)
            TodayFocusCell(store: store).gridCell(0, 1, columns: 2)
            TodayBTCell(store: store).gridCell(2, 1, columns: 2)
            TodayGreetingCell(store: store).gridCell(0, 2, columns: 2)
            TodayComposerCell(store: store).gridCell(2, 2, columns: 2)
        }
    }
}

/// Column 4 of the header while Today is open.
public struct TodayHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Button {
            store.route = .bt
        } label: {
            HStack(spacing: 10) {
                Text("Ask BT").foregroundStyle(Color.btInk)
                Text("⌘K").foregroundStyle(Color.btMuted)
            }
            .monoLabel()
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(Capsule().strokeBorder(Color.btInk, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k")
        .accessibilityLabel("Ask BT")
    }
}
