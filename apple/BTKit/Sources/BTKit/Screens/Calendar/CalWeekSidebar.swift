import SwiftUI

/// Week column 1: mini month, calendar layers, "Due this week".
struct CalWeekSidebar: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CalMiniMonth(store: store)
            layers
            dueThisWeek
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var layers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars").monoLabel()
            ForEach(CalWeekLayer.allCases, id: \.self) { layer in
                CalLayerRow(layer: layer, state: store.calendarScreen)
            }
        }
    }

    private var dueThisWeek: some View {
        let cal = store.calendar
        let days = CalDates.weekDays(store.calendarDate, cal)
        let end = cal.date(byAdding: .day, value: 7, to: days[0])!
        let dues = store.events.filter { $0.kind == .deadline && $0.start >= days[0] && $0.start < end }
            .sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Due this week").monoLabel()
            if dues.isEmpty {
                Text("Nothing due.").foregroundStyle(Color.btMuted)
            }
            ForEach(dues) { due in
                let soon = due.end > store.now && due.end.timeIntervalSince(store.now) < 86400
                Button {
                    store.open(.calendar(.day, date: due.start))
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(due.title).font(.inter(14, .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(soon ? CalFormat.countdown(from: store.now, to: due.end) : CalFormat.string(due.start, "EEE", cal))
                            .font(.mono(12))
                            .foregroundStyle(soon ? Color.btAccentText : .btMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One checkbox row: swatch, name, source.
private struct CalLayerRow: View {
    let layer: CalWeekLayer
    @Bindable var state: CalendarScreenState

    var body: some View {
        let on = Binding(
            get: { !state.hiddenWeekLayers.contains(layer) },
            set: { show in if show { state.hiddenWeekLayers.remove(layer) } else { state.hiddenWeekLayers.insert(layer) } }
        )
        Toggle(isOn: on) {
            HStack(spacing: 10) {
                CalSwatch(kind: layer.swatchKind, size: 10)
                Text(layer.name).font(.inter(14)).frame(maxWidth: .infinity, alignment: .leading)
                Text(layer.source).font(.mono(10)).foregroundStyle(Color.btMuted)
            }
        }
        .toggleStyle(CalCheckboxStyle(size: 16))
        .accessibilityLabel(layer.name)
    }
}

/// Small square showing a block kind's fill and border.
struct CalSwatch: View {
    let kind: EventKind
    var size: CGFloat = 7

    var body: some View {
        Rectangle()
            .fill(kind == .studyPlanned || kind == .btDraft ? Color.clear : EventBlockView.fill(kind))
            .overlay(border)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .classSession, .work:
            Rectangle().strokeBorder(Color.btSubtle, lineWidth: 1)
        case .studyPlanned:
            Rectangle().strokeBorder(Color.btInk, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1]))
        case .btDraft:
            Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1]))
        case .focusLogged, .deadline:
            EmptyView()
        }
    }
}

/// Mini month: shown week shaded, today in accent. Tapping a date moves the week.
struct CalMiniMonth: View {
    @Bindable var store: AppStore

    var body: some View {
        let cal = store.calendar
        let days = CalDates.monthGrid(store.calendarDate, cal)
        let week = Set(CalDates.weekDays(store.calendarDate, cal).map { cal.startOfDay(for: $0) })
        VStack(spacing: 10) {
            HStack {
                Text(CalFormat.string(store.calendarDate, "MMMM yyyy", cal)).monoLabel()
                Spacer()
                Button("Month →") { store.calendarMode = .month }.buttonStyle(.monoLink)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.mono(11)).foregroundStyle(Color.btMuted)
                }
                ForEach(days, id: \.self) { day in
                    let inMonth = cal.isDate(day, equalTo: store.calendarDate, toGranularity: .month)
                    let isToday = cal.isDate(day, inSameDayAs: store.now)
                    Button { store.calendarDate = day } label: {
                        Text("\(cal.component(.day, from: day))")
                            .font(.mono(11))
                            .foregroundStyle(isToday ? Color.btOnAccent : inMonth ? .btInk : .btSubtle)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(Capsule().fill(isToday ? Color.btAccent : week.contains(day) ? .btFillClass : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CalFormat.string(day, "EEEE MMMM d", cal))
                }
            }
        }
    }
}
