import SwiftUI

/// The redesigned app window: the Sand Grid header over the selected module.
public struct BTAppView: View {
    @Bindable var store: AppStore

    public init(store: AppStore) {
        BTFont.register()
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            AppHeader(store: store)
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: BTMetrics.minContentWidth, minHeight: 760)
        .background(Color.btGround)
        .foregroundStyle(Color.btInk)
        .font(.inter(14))
        .tint(.btAccent)
        // Here, not on Focus, so a break that starts on another screen still pauses music.
        .onChange(of: store.focus.mode) { _, mode in
            if mode == .break { store.pauseMusicForBreak() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.tick()
            }
        }
    }

    @ViewBuilder private var screen: some View {
        switch store.route {
        case .today: TodayScreen(store: store)
        case .focus: FocusScreen(store: store)
        case .code: CodeScreen(store: store)
        case .calendar: CalendarScreen(store: store)
        case .bt: BTScreen(store: store)
        }
    }
}

/// 52pt bar on the 4-column grid: wordmark, module nav, and a context slot each screen sets.
struct AppHeader: View {
    @Bindable var store: AppStore

    var body: some View {
        SandGrid(columns: 4, rows: [1]) {
            HStack(spacing: 18) {
                // The window's own traffic lights sit here (hidden title bar).
                Color.clear.frame(width: 52, height: 12)
                Text("B T").font(.inter(13, .semibold)).tracking(13 * 0.32)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .gridCell(0, 0)

            HStack(spacing: 28) {
                ForEach(AppRoute.allCases, id: \.self) { route in
                    navItem(route)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .gridCell(1, 0, columns: 2)

            context
                .monoLabel()
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .gridCell(3, 0)
        }
        .frame(height: BTMetrics.headerHeight)
        .dashedEdges(right: false, bottom: true)
    }

    private func navItem(_ route: AppRoute) -> some View {
        let active = store.route == route
        return Button {
            store.route = route
        } label: {
            Text(route.title)
                .monoLabel(color: active ? .btInk : .btMuted)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    if active { Rectangle().fill(Color.btInk).frame(height: 1.5) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(AppRoute.allCases.firstIndex(of: route)! + 1)")), modifiers: .command)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private var context: some View {
        switch store.route {
        case .today: TodayHeaderContext(store: store)
        case .focus: FocusHeaderContext(store: store)
        case .code: CodeHeaderContext(store: store)
        case .calendar: CalendarHeaderContext(store: store)
        case .bt: BTHeaderContext(store: store)
        }
    }
}

#Preview("App") {
    BTAppView(store: AppStore())
        .frame(width: 1440, height: 900)
}
