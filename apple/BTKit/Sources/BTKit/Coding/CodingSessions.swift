import Foundation

/// A session ends after this long without a heartbeat.
let codingIdleCutoff: TimeInterval = 15 * 60
/// The time a heartbeat stands for, matching the extension's throttle.
let codingBeatLength: TimeInterval = 60

struct CodingSession: Equatable {
    var start: Date
    var end: Date
    var project: String
    var language: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Groups heartbeats into sessions. A gap over `idle` or a project change starts
/// a new session. A session lasts until its last beat plus a minute, but no later
/// than the next session's start, so switching projects never double counts.
func sessionize(_ beats: [Heartbeat], idle: TimeInterval = codingIdleCutoff) -> [CodingSession] {
    var groups: [[Heartbeat]] = []
    for beat in beats.sorted(by: { $0.timestamp < $1.timestamp }) {
        if let last = groups.last?.last,
           last.project == beat.project,
           beat.timestamp.timeIntervalSince(last.timestamp) <= idle {
            groups[groups.count - 1].append(beat)
        } else {
            groups.append([beat])
        }
    }
    return groups.indices.map { index in
        let group = groups[index]
        var end = group[group.count - 1].timestamp + codingBeatLength
        if index + 1 < groups.count {
            end = min(end, groups[index + 1][0].timestamp)
        }
        return CodingSession(start: group[0].timestamp, end: end, project: group[0].project, language: majorityLanguage(group))
    }
}

/// The most frequent language; ties go to the one seen latest.
private func majorityLanguage(_ group: [Heartbeat]) -> String {
    var counts: [String: Int] = [:]
    var lastSeen: [String: Int] = [:]
    for (index, beat) in group.enumerated() {
        counts[beat.language, default: 0] += 1
        lastSeen[beat.language] = index
    }
    return counts.keys.max { a, b in
        (counts[a]!, lastSeen[a]!) < (counts[b]!, lastSeen[b]!)
    } ?? ""
}

struct CodingDayTotal: Equatable {
    var day: Date
    var seconds: TimeInterval
}

struct CodingTotal: Equatable {
    var name: String
    var seconds: TimeInterval
}

struct CodingStats: Equatable {
    var total: TimeInterval
    /// One entry per day in the range, oldest first, including empty days.
    var perDay: [CodingDayTotal]
    /// Sorted by time, descending.
    var byProject: [CodingTotal]
    var byLanguage: [CodingTotal]
}

/// The days in a range ending on `endingOn`, oldest first, as start-of-day dates.
func codingDays(_ days: Int, endingOn day: Date, calendar: Calendar) -> [Date] {
    let last = calendar.startOfDay(for: day)
    return (0..<max(days, 0)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
}

/// Totals for the `days` days ending on `endingOn`. A session counts toward the day it started.
func codingStats(_ sessions: [CodingSession], days: Int, endingOn day: Date, calendar: Calendar) -> CodingStats {
    let dayStarts = codingDays(days, endingOn: day, calendar: calendar)
    let inRange = sessions.filter { dayStarts.contains(calendar.startOfDay(for: $0.start)) }
    let perDay = dayStarts.map { start in
        CodingDayTotal(day: start, seconds: inRange.filter { calendar.startOfDay(for: $0.start) == start }.reduce(0) { $0 + $1.duration })
    }
    return CodingStats(
        total: inRange.reduce(0) { $0 + $1.duration },
        perDay: perDay,
        byProject: totals(inRange, by: \.project),
        byLanguage: totals(inRange, by: \.language)
    )
}

private func totals(_ sessions: [CodingSession], by key: KeyPath<CodingSession, String>) -> [CodingTotal] {
    Dictionary(grouping: sessions, by: { $0[keyPath: key] })
        .map { CodingTotal(name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.duration }) }
        .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
}
