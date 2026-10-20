import SwiftUI

struct WeekView: View {
    let module: CalendarModule
    let events: [CalendarEventItem]

    var body: some View {
        let calendar = Calendar.current
        let days = weekDays(containing: module.focusDate, calendar: calendar)
        let splits = days.map { items(events, on: $0, calendar: calendar) }
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 2) {
                Color.clear.frame(width: 44, height: 1)
                ForEach(days.indices, id: \.self) { index in
                    let isToday = calendar.isDateInToday(days[index])
                    VStack(spacing: 2) {
                        Text(days[index].formatted(.dateTime.weekday(.abbreviated).day()))
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : .primary)
                        ForEach(splits[index].allDay) { EventChip(event: $0) }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        module.focusDate = days[index]
                        module.mode = .day
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 2) {
                        HourLabels()
                        ForEach(days.indices, id: \.self) { index in
                            TimelineColumn(day: days[index], events: splits[index].timed)
                                .background(calendar.isDateInToday(days[index]) ? Color.accentColor.opacity(0.06) : .clear)
                        }
                    }
                    .padding()
                }
                .onAppear { proxy.scrollTo(initialScrollHour(showingToday: days.contains(where: calendar.isDateInToday)), anchor: .top) }
            }
        }
    }
}
