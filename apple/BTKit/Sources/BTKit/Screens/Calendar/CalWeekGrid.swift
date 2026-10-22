import SwiftUI

/// Column geometry shared by the header rows and the time grid: a 44pt hour gutter, then 7 days.
struct CalWeekColumns {
    static let gutter: CGFloat = 44
    static let gap: CGFloat = 6
    let width: CGFloat

    var columnWidth: CGFloat { max(0, (width - Self.gutter - Self.gap * 7) / 7) }
    func x(_ day: Int) -> CGFloat { Self.gutter + Self.gap + CGFloat(day) * (columnWidth + Self.gap) }
}

/// Week columns 2–4: day headers, DUE row, the 8 AM–10 PM grid, and the BT bar.
struct CalWeekGrid: View {
    @Bindable var store: AppStore

    private var cal: Calendar { store.calendar }
    private var days: [Date] { CalDates.weekDays(store.calendarDate, cal) }
    private var visible: [CalendarEvent] { CalLayers.visible(store.events, hiding: store.calendarScreen.hiddenWeekLayers) }

    var body: some View {
        VStack(spacing: 8) {
            columnsRow(minHeight: 28) { i, day in dayHeader(day) }
            columnsRow(label: "DUE", minHeight: 24) { _, day in dueTags(day) }
            GeometryReader { geo in timeGrid(size: geo.size) }
            CalWeekBTBar(store: store)
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
    }

    // MARK: Header rows

    private func columnsRow<C: View>(label: String? = nil, minHeight: CGFloat, @ViewBuilder cell: @escaping (Int, Date) -> C) -> some View {
        HStack(alignment: .top, spacing: CalWeekColumns.gap) {
            Text(label ?? "").font(.mono(10)).foregroundStyle(Color.btMuted)
                .frame(width: CalWeekColumns.gutter, alignment: .leading)
                .frame(minHeight: minHeight)
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                cell(i, day).frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: store.now)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(CalFormat.string(day, "EEE", cal)).monoLabel(color: isToday ? .btAccentText : .btInk)
            Text("\(cal.component(.day, from: day))").interStyle(22, .medium, tracking: -0.03)
                .foregroundStyle(isToday ? Color.btAccentText : .btInk)
        }
        .padding(.horizontal, 4)
    }

    private func dueTags(_ day: Date) -> some View {
        let dues = visible.filter { $0.kind == .deadline && cal.isDate($0.start, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(dues) { due in
                Button { store.open(.calendar(.day, date: due.start)) } label: {
                    DueTag(due.title)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .background(Color.btAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(due.title) due, open day")
            }
        }
    }

    // MARK: Time grid

    private func timeGrid(size: CGSize) -> some View {
        let cols = CalWeekColumns(width: size.width)
        let selected = store.selectedEventID.flatMap { id in visible.first { $0.id == id && $0.kind != .deadline } }
        let selectedDay = selected.flatMap { e in days.firstIndex { cal.isDate($0, inSameDayAs: e.start) } }
        return ZStack(alignment: .topLeading) {
            hourLabels.frame(width: CalWeekColumns.gutter, height: size.height)
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                dayColumn(day, height: size.height)
                    .frame(width: cols.columnWidth, height: size.height)
                    .offset(x: cols.x(i))
            }
            if let selected, let selectedDay {
                let block = CalTimeline.frame(start: selected.start, end: selected.end, height: size.height, cal: cal)
                CalEventPopover(store: store, event: selected)
                    .frame(width: CalPopover.width)
                    .offset(
                        x: CalPopover.x(dayIndex: selectedDay, columnX: cols.x, columnWidth: cols.columnWidth),
                        y: CalPopover.y(blockY: block.y, gridHeight: size.height)
                    )
                    .zIndex(2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var hourLabels: some View {
        VStack(alignment: .leading) {
            ForEach(["8a", "10a", "12p", "2p", "4p", "6p", "8p", "10p"], id: \.self) { h in
                Text(h).font(.mono(10)).foregroundStyle(Color.btMuted)
                if h != "10p" { Spacer(minLength: 0) }
            }
        }
        .accessibilityHidden(true)
    }

    private func dayColumn(_ day: Date, height: CGFloat) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: store.now)
        let events = visible.filter { $0.kind != .deadline && cal.isDate($0.start, inSameDayAs: day) }
        return ZStack(alignment: .topLeading) {
            (isToday ? Color.btAccent.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { store.selectedEventID = nil }
            DashedEdges(right: false, bottom: false, left: true)
                .stroke(Color.btTrack, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash))
                .allowsHitTesting(false)
            ForEach(events) { e in block(e, height: height) }
            if isToday, CalTimeline.isVisible(store.now, cal) {
                nowLine(y: CGFloat(CalTimeline.fraction(store.now, cal)) * height)
            }
        }
    }

    private func block(_ e: CalendarEvent, height: CGFloat) -> some View {
        let f = CalTimeline.frame(start: e.start, end: e.end, height: height, cal: cal)
        let title = e.kind == .focusLogged ? [e.title, e.focusPlan].compactMap { $0 }.joined(separator: " · ") : e.title
        let detail = CalFormat.time(e.start, cal) + (e.kind == .btDraft ? " · BT draft" : "")
        let isSelected = store.selectedEventID == e.id
        return Button { store.calSelect(e.id) } label: {
            EventBlockView(title: title, detail: f.height >= 34 ? detail : nil, kind: e.kind, isSelected: isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .frame(height: f.height)
        .offset(y: f.y)
        .accessibilityLabel("\(title), \(CalFormat.range(e.start, e.end, cal)), \(CalFormat.kindLabel(e.kind))")
        .accessibilityAddTraits(store.selectedEventID == e.id ? .isSelected : [])
    }

    private func nowLine(y: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.btAccent).frame(height: 2).padding(.leading, -4)
            Circle().fill(Color.btAccent).frame(width: 9, height: 9).offset(x: -7)
        }
        .frame(height: 9)
        .offset(y: y - 4.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
