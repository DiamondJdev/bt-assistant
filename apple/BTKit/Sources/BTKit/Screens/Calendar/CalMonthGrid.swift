import SwiftUI

/// Month columns 1–3: a Monday-first month grid filtered by the layer pills. Clicking selects a day.
struct CalMonthGrid: View {
    @Bindable var store: AppStore

    private var cal: Calendar { store.calendar }

    var body: some View {
        let days = CalDates.monthGrid(store.calendarDate, cal)
        let visible = CalLayers.visible(store.calVisibleEvents, showing: store.calendarScreen.monthLayers)
        let rows = days.count / 7
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                    Text(d).monoLabel().padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .dashedEdges(right: false, bottom: true)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(days[(r * 7)..<(r * 7 + 7)], id: \.self) { day in
                            CalMonthCell(store: store, day: day, events: visible.filter { cal.isDate($0.start, inSameDayAs: day) },
                                         allDay: store.allDayEvents(on: day))
                        }
                    }
                }
            }
        }
    }
}

private struct CalMonthCell: View {
    @Bindable var store: AppStore
    let day: Date
    let events: [CalendarEvent]
    let allDay: [CalendarEvent]

    var body: some View {
        let cal = store.calendar
        let inMonth = cal.isDate(day, equalTo: store.calendarDate, toGranularity: .month)
        let isToday = cal.isDate(day, inSameDayAs: store.now)
        let isSelected = inMonth && cal.isDate(day, inSameDayAs: store.calendarDate)
        let isPast = cal.startOfDay(for: day) < cal.startOfDay(for: store.now)
        let due = events.first { $0.kind == .deadline }
        let items = events.filter { $0.kind != .deadline }
        let load = inMonth ? CalMonthMath.load(day: day, events: store.events(on: day), cal: cal) : 0

        Button {
            if inMonth { store.calendarDate = day }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(cal.component(.day, from: day))")
                        .interStyle(18, .medium, tracking: -0.03)
                        .foregroundStyle(isToday ? Color.btOnAccent : inMonth ? .btInk : .btSubtle)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(Circle().fill(isToday ? Color.btAccent : .clear))
                    Spacer(minLength: 0)
                    if inMonth, let due {
                        Text(due.title).font(.inter(10, .semibold)).foregroundStyle(Color.btOnAccent).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.btAccent)
                    }
                }
                Rectangle().fill(Color.btFillClass).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Rectangle().fill(isPast ? Color.btSubtle : .btInk).frame(width: g.size.width * load)
                        }
                    }
                if inMonth {
                    ForEach(allDay.prefix(2)) { AllDayTag($0.title) }
                    ForEach(items.prefix(max(0, 3 - min(2, allDay.count)))) { e in
                        HStack(spacing: 6) {
                            CalSwatch(kind: e.kind)
                            Text(CalMonthMath.itemTitle(e)).font(.inter(11)).lineLimit(1)
                                .foregroundStyle(isPast ? Color.btMuted : .btInk)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background(inMonth: inMonth, isToday: isToday, isSelected: isSelected))
            .overlay(isSelected ? Rectangle().strokeBorder(Color.btAccent, lineWidth: 1.5) : nil)
            .overlay(
                DashedEdges().stroke(Color.btTrack, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)).allowsHitTesting(false)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
        .accessibilityLabel(accessibilityLabel(due: due, itemCount: items.count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(due: CalendarEvent?, itemCount: Int) -> String {
        let date = CalFormat.string(day, "EEEE MMMM d", store.calendar)
        let dueText = due.map { ", \($0.title) due" } ?? ""
        let allDayText = allDay.map { ", \($0.title) all day" }.joined()
        return date + dueText + allDayText + ", \(itemCount) items"
    }

    private func background(inMonth: Bool, isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Color.btAccent.opacity(0.10) }
        if isToday { return Color.btAccent.opacity(0.05) }
        return inMonth ? .clear : Color(hex: 0xE2D7CA)
    }
}
