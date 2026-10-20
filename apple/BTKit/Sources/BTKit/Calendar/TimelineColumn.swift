import SwiftUI

let hourHeight: CGFloat = 48

/// Side-by-side placement for overlapping timed events: column index and column count per event id.
func timelineLayout(_ events: [CalendarEventItem]) -> [String: (column: Int, columns: Int)] {
    var result: [String: (column: Int, columns: Int)] = [:]
    var cluster: [(id: String, column: Int)] = []
    var columnEnds: [Date] = []
    var clusterEnd = Date.distantPast

    func closeCluster() {
        for entry in cluster { result[entry.id] = (entry.column, columnEnds.count) }
        cluster = []
        columnEnds = []
    }

    for event in events.sorted(by: { $0.start < $1.start }) {
        if event.start >= clusterEnd { closeCluster() }
        if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
            columnEnds[free] = event.end
            cluster.append((event.id, free))
        } else {
            columnEnds.append(event.end)
            cluster.append((event.id, columnEnds.count - 1))
        }
        clusterEnd = max(clusterEnd, event.end)
    }
    closeCluster()
    return result
}

/// One day's 24-hour timeline: hour lines, timed events and the now line.
struct TimelineColumn: View {
    let day: Date
    let events: [CalendarEventItem]

    var body: some View {
        let calendar = Calendar.current
        let layout = timelineLayout(events)
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .offset(y: CGFloat(hour) * hourHeight)
                }
                ForEach(events) { event in
                    let top = minutesIntoDay(event.start, day: day, calendar: calendar) / 60 * hourHeight
                    let bottom = minutesIntoDay(event.end, day: day, calendar: calendar) / 60 * hourHeight
                    let slot = layout[event.id] ?? (0, 1)
                    let width = geometry.size.width / CGFloat(slot.columns)
                    EventBlock(event: event)
                        .frame(width: max(width - 2, 0), height: max(bottom - top, 18))
                        .offset(x: CGFloat(slot.column) * width, y: top)
                }
                if calendar.isDateInToday(day) {
                    TimelineView(.everyMinute) { context in
                        Rectangle()
                            .fill(.red)
                            .frame(height: 2)
                            .offset(y: minutesIntoDay(context.date, day: day, calendar: calendar) / 60 * hourHeight)
                    }
                }
            }
        }
        .frame(height: hourHeight * 24)
    }
}

struct HourLabels: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
            }
        }
        .frame(width: 44, alignment: .trailing)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return date.formatted(.dateTime.hour())
    }
}

struct EventBlock: View {
    let event: CalendarEventItem

    var body: some View {
        let color = Color(hex: event.colorHex)
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title).font(.caption.weight(.semibold))
            Text(event.start, format: .dateTime.hour().minute()).font(.caption2)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// A one-line colored label, used in all-day strips and month cells.
struct EventChip: View {
    let event: CalendarEventItem

    var body: some View {
        Text(event.title)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: event.colorHex).opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
    }
}

extension Color {
    /// `#RRGGBB` from `CalendarEventItem.colorHex`, or the accent color.
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else {
            self = .accentColor
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
