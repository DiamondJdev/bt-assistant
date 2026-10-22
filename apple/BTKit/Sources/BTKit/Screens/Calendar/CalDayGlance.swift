import SwiftUI

/// Day column 4: today's hours as a stacked bar, and "Due soon" countdowns.
struct CalDayGlance: View {
    @Bindable var store: AppStore

    private var cal: Calendar { store.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            hours
            dueSoon
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hours: some View {
        let b = CalHoursBreakdown(day: store.calendarDate, events: store.events(on: store.calendarDate), cal: cal)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(cal.isDate(store.calendarDate, inSameDayAs: store.now) ? "Today’s hours" : "Hours").monoLabel()
                Spacer()
                Text("9a – 11p").monoLabel()
            }
            CalStackedBar(segments: [
                (b.classHours, .solid(.btFillClass)),
                (b.focusHours, .solid(.btInk)),
                (b.openHours, .hatch),
                (b.otherHours, .solid(.btTrack)),
            ])
            .frame(height: 36)
            .accessibilityElement()
            .accessibilityLabel("Class \(CalFormat.hours(b.classHours)), focus planned \(CalFormat.hours(b.focusHours)), open \(CalFormat.hours(b.openHours)), other \(CalFormat.hours(b.otherHours))")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    stat(CalFormat.hours(b.classHours), "Class")
                    stat(CalFormat.hours(b.focusHours), "Focus planned")
                }
                GridRow {
                    stat(CalFormat.hours(b.openHours), "Open")
                    stat(CalFormat.hours(Double(store.focusedTodaySeconds) / 3600), "Focused so far")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).interStyle(26, .medium, tracking: -0.03)
            Text(label).font(.inter(12)).foregroundStyle(Color.btMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dueSoon: some View {
        let items = CalDueSoon.list(now: store.now, events: store.events)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Due soon").monoLabel()
            if items.isEmpty { Text("Nothing due.").foregroundStyle(Color.btMuted) }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let left = item.deadline.end.timeIntervalSince(store.now)
                Button { store.open(.calendar(.day, date: item.deadline.start)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.deadline.title).font(.inter(17, .medium)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(CalFormat.countdown(from: store.now, to: item.deadline.end))
                                .interStyle(26, .medium, tracking: -0.03)
                                .foregroundStyle(left < 86400 ? Color.btAccentText : .btInk)
                        }
                        Text(note(item)).font(.inter(12)).foregroundStyle(item.booked.isEmpty ? Color.btAccentDeep : .btMuted)
                    }
                    .padding(.bottom, i < items.count - 1 ? 12 : 0)
                    .overlay(alignment: .bottom) {
                        if i < items.count - 1 { Rectangle().fill(Color.btRule).frame(height: 1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func note(_ item: CalDueSoon) -> String {
        guard let first = item.booked.first else { return "No time booked yet" }
        let when = CalFormat.string(first.start, "EEE", cal) + " " + CalFormat.time(first.start, cal)
        return item.booked.count == 1 ? "1 study block booked · \(when)" : "\(item.booked.count) study blocks booked · first \(when)"
    }
}

/// Horizontal bar of proportional segments with 2pt gaps.
struct CalStackedBar: View {
    enum Fill { case solid(Color), hatch }
    let segments: [(Double, Fill)]

    var body: some View {
        GeometryReader { geo in
            let shown = segments.filter { $0.0 > 0 }
            let total = shown.reduce(0) { $0 + $1.0 }
            let free = geo.size.width - CGFloat(max(0, shown.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, s in
                    Group {
                        switch s.1 {
                        case .solid(let c): Rectangle().fill(c)
                        case .hatch: CalHatch(spacing: 5, lineWidth: 1)
                        }
                    }
                    .frame(width: total > 0 ? free * CGFloat(s.0 / total) : 0)
                }
            }
        }
    }
}
