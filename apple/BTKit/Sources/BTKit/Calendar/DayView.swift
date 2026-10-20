import SwiftUI

struct DayView: View {
    let module: CalendarModule
    let events: [CalendarEventItem]

    var body: some View {
        let calendar = Calendar.current
        let day = module.focusDate
        let isToday = calendar.isDateInToday(day)
        let split = items(events, on: day, calendar: calendar)
        VStack(spacing: 0) {
            if isToday {
                NextUpRow(module: module)
                Divider()
            }
            if !split.allDay.isEmpty {
                ScrollView(.horizontal) {
                    HStack { ForEach(split.allDay) { EventChip(event: $0).frame(width: 160).eventDetailsOnTap($0, module: module) } }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 6) {
                        HourLabels()
                        TimelineColumn(module: module, day: day, events: split.timed)
                    }
                    .padding()
                }
                .onAppear { proxy.scrollTo(initialScrollHour(showingToday: isToday), anchor: .top) }
            }
        }
    }
}

/// "Next up": the next timed event from now, within the coming week.
struct NextUpRow: View {
    let module: CalendarModule

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = module.store.changeToken
            HStack(spacing: 8) {
                Text("Next up").font(.headline)
                if let next = module.store.nextEvent(after: context.date) {
                    Circle().fill(Color(hex: next.colorHex)).frame(width: 8, height: 8)
                    Text(next.title).lineLimit(1)
                    Text(timeText(next.start)).foregroundStyle(.secondary)
                    Text("in \(formattedDuration(next.start.timeIntervalSince(context.date)))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing in the next week").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func timeText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday().hour().minute())
    }
}
