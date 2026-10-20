import SwiftUI

struct MonthView: View {
    let module: CalendarModule
    let events: [CalendarEventItem]

    private let maxTitles = 3

    var body: some View {
        let calendar = Calendar.current
        let days = monthGridDays(containing: module.focusDate, calendar: calendar)
        let rows = days.count / 7
        let symbols = calendar.shortWeekdaySymbols
        let weekdayOrder = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdayOrder, id: \.self) { symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            Divider()
            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(rows)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        cell(day, calendar: calendar)
                            .frame(height: rowHeight, alignment: .top)
                            .border(Color.secondary.opacity(0.2), width: 0.5)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, calendar: Calendar) -> some View {
        let split = items(events, on: day, calendar: calendar)
        let dayEvents = split.allDay + split.timed
        let inMonth = calendar.isDate(day, equalTo: module.focusDate, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : inMonth ? .primary : .secondary)
                    .padding(3)
                    .background(isToday ? Color.accentColor : .clear, in: Circle())
            }
            ForEach(dayEvents.prefix(maxTitles)) { EventChip(event: $0) }
            if dayEvents.count > maxTitles {
                Text("+\(dayEvents.count - maxTitles) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(3)
        .opacity(inMonth ? 1 : 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            module.focusDate = day
            module.mode = .day
        }
    }
}
