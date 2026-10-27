import Foundation

enum CalWeekLayout {
    struct Placed {
        var event: CalendarEvent
        var indent: Int
        var groupID: Int
        var col = 0
        var cols = 1
        var z: Int
    }

    static func cascade(_ events: [CalendarEvent]) -> [Placed] {
        let sorted = events.sorted {
            $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start
        }
        var placed: [Placed] = []
        var groups: [[Int]] = []

        for (index, event) in sorted.enumerated() {
            let overlapping = placed.indices.filter { placed[$0].event.end > event.start }
            let close = overlapping.first {
                event.start.timeIntervalSince(placed[$0].event.start) < 30 * 60
            }
            let indent: Int
            let groupID: Int

            if let close {
                indent = placed[close].indent
                groupID = placed[close].groupID
                groups[groupID].append(placed.count)
            } else {
                indent = overlapping.map { placed[$0].indent + 1 }.max() ?? 0
                groupID = groups.count
                groups.append([placed.count])
            }

            placed.append(Placed(event: event, indent: indent, groupID: groupID, z: 10 + index))
        }

        for group in groups {
            for (column, index) in group.enumerated() {
                placed[index].col = column
                placed[index].cols = group.count
            }
        }
        return placed
    }
}
