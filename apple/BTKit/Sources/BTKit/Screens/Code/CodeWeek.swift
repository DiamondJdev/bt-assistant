import Foundation

/// What a project's status line says in the project list.
enum CodeStatus: Equatable {
    case codingNow
    case dropping(percent: Int)
    case lastTouched(weekday: String?)
    case idle(days: Int)
    case noActivity

    var label: String {
        switch self {
        case .codingNow: "● Coding now"
        case .dropping(let p): "\u{2212}\(abs(p))% vs avg"
        case .lastTouched(let day): "Last touched \(day ?? "today")"
        case .idle(let days): "Idle \(days) day\(days == 1 ? "" : "s")"
        case .noActivity: "No activity yet"
        }
    }

    /// Accent when active or dropping.
    var isAccent: Bool {
        switch self {
        case .codingNow, .dropping: true
        default: false
        }
    }
}

/// One heat grid cell: an intensity level 0…4, or a slot that hasn't happened yet.
enum HeatCell: Equatable {
    case level(Int)
    case future
}

/// Metrics for one project's activity in the week containing `now`. Everything is derived from
/// `CodingActivity` (agent runs, reviews, manual edits), clipped to the interval asked about.
struct CodeWeek {
    static let firstHour = 8
    static let hourColumns = 16
    static let averageWeeks = 3
    /// "Coding now" if the latest run ended this recently.
    static let liveSlack: TimeInterval = 10 * 60
    /// A drop at least this large vs the average shows as a status.
    static let dropThreshold = -0.25
    static let idleDays = 7

    let activity: [CodingActivity]
    let now: Date
    let calendar: Calendar
    let week: DateInterval

    init(activity: [CodingActivity], now: Date, calendar: Calendar) {
        self.activity = activity
        self.now = now
        self.calendar = calendar
        week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
    }

    // MARK: Totals

    func minutes(in interval: DateInterval) -> Double {
        activity.reduce(0) { total, run in
            guard run.end > run.start, let overlap = interval.intersection(with: DateInterval(start: run.start, end: run.end))
            else { return total }
            return total + overlap.duration / 60
        }
    }

    var weekMinutes: Double { minutes(in: week) }

    func day(_ index: Int) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: index, to: week.start)!
        return calendar.dateInterval(of: .day, for: start)!
    }

    /// Monday-first index of today within the week.
    var todayIndex: Int {
        calendar.dateComponents([.day], from: week.start, to: calendar.startOfDay(for: now)).day ?? 0
    }

    var dailyMinutes: [Double] { (0..<7).map { minutes(in: day($0)) } }

    func weekBefore(_ n: Int) -> DateInterval {
        let start = calendar.date(byAdding: .weekOfYear, value: -n, to: week.start)!
        return DateInterval(start: start, end: calendar.date(byAdding: .weekOfYear, value: 1, to: start)!)
    }

    var lastWeekMinutes: Double { minutes(in: weekBefore(1)) }

    /// Average of the previous full weeks; nil when there's no history to compare against.
    var averageMinutes: Double? {
        let total = (1...Self.averageWeeks).reduce(0) { $0 + minutes(in: weekBefore($1)) }
        return total > 0 ? total / Double(Self.averageWeeks) : nil
    }

    // MARK: Status

    var status: CodeStatus {
        if activity.contains(where: { $0.start <= now && $0.end >= now.addingTimeInterval(-Self.liveSlack) }) {
            return .codingNow
        }
        guard let last = activity.filter({ $0.start <= now }).map(\.end).max() else { return .noActivity }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        if days >= Self.idleDays { return .idle(days: days) }
        if let avg = averageMinutes {
            let change = weekMinutes / avg - 1
            if change <= Self.dropThreshold { return .dropping(percent: Int((change * 100).rounded())) }
        }
        if days == 0 { return .lastTouched(weekday: nil) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return .lastTouched(weekday: formatter.string(from: last))
    }

    /// Consecutive days with activity, counting back from today (or yesterday if today is empty so far).
    var streakDays: Int {
        var dayStart = calendar.startOfDay(for: now)
        var count = 0
        var isToday = true
        while true {
            let interval = calendar.dateInterval(of: .day, for: dayStart)!
            if minutes(in: interval) > 0 {
                count += 1
            } else if !isToday {
                return count
            }
            isToday = false
            dayStart = calendar.date(byAdding: .day, value: -1, to: dayStart)!
        }
    }

    // MARK: Heat grid

    func hourCell(day index: Int, column: Int) -> DateInterval {
        let start = calendar.date(bySettingHour: Self.firstHour + column, minute: 0, second: 0, of: day(index).start)!
        return DateInterval(start: start, duration: 3600)
    }

    /// 7 day rows × 16 hour columns (8 AM to midnight). Slots that start after now are `.future`.
    var heat: [[HeatCell]] {
        (0..<7).map { d in
            (0..<Self.hourColumns).map { h in
                let cell = hourCell(day: d, column: h)
                return cell.start > now ? .future : .level(Self.level(minutes: minutes(in: cell)))
            }
        }
    }

    static func level(minutes: Double) -> Int {
        switch minutes {
        case ..<0.5: 0
        case ..<15: 1
        case ..<30: 2
        case ..<45: 3
        default: 4
        }
    }

    /// Start hour of the busiest 2-hour window across the week; nil with no activity.
    var bestStartHour: Int? {
        let columns = (0..<Self.hourColumns).map { h in (0..<7).reduce(0) { $0 + minutes(in: hourCell(day: $1, column: h)) } }
        let pairs = (0..<Self.hourColumns - 1).map { columns[$0] + columns[$0 + 1] }
        guard let best = pairs.max(), best > 0, let i = pairs.firstIndex(of: best) else { return nil }
        return Self.firstHour + i
    }

    /// "Best: 8 – 10 PM".
    var bestWindow: String {
        bestStartHour.map { "Best: " + Self.hourRange($0, $0 + 2, spaced: true) } ?? "No data yet"
    }

    /// "8 – 10 PM", "11 AM – 1 PM"; unspaced "8–10 PM" for button copy.
    static func hourRange(_ start: Int, _ end: Int, spaced: Bool) -> String {
        func parts(_ h: Int) -> (Int, String) {
            let h24 = h % 24
            return (h24 % 12 == 0 ? 12 : h24 % 12, h24 < 12 ? "AM" : "PM")
        }
        let (a, am) = parts(start), (b, bm) = parts(end)
        let dash = spaced ? " – " : "–"
        return am == bm ? "\(a)\(dash)\(b) \(bm)" : "\(a) \(am)\(dash)\(b) \(bm)"
    }

    // MARK: Inside Focus

    private var weekRuns: [CodingActivity] {
        activity.filter { $0.end > week.start && $0.start < week.end && $0.start <= now }
    }

    /// Share of this week's minutes inside a Focus session, 0…1; nil with no work.
    var insideShare: Double? {
        let total = weekMinutes
        guard total > 0 else { return nil }
        let inside = activity.filter { $0.insideFocusSessionID != nil }
        return CodeWeek(activity: inside, now: now, calendar: calendar).weekMinutes / total
    }

    /// Average unbroken run length in minutes, inside and outside Focus.
    var unbroken: (inside: Int?, outside: Int?) {
        func average(_ runs: [CodingActivity]) -> Int? {
            runs.isEmpty ? nil : Int((runs.reduce(0) { $0 + $1.duration } / 60 / Double(runs.count)).rounded())
        }
        let runs = weekRuns
        return (average(runs.filter { $0.insideFocusSessionID != nil }), average(runs.filter { $0.insideFocusSessionID == nil }))
    }

    var insideNote: String {
        switch unbroken {
        case (nil, nil): "No sessions this week."
        case (nil, let out?): "No Focus sessions this week. \(out) min unbroken outside one."
        case (let inside?, let out): "\(inside) min unbroken inside a session. \(out ?? 0) outside."
        }
    }

    // MARK: Formatting

    /// "5h 40m", "0h 07m".
    static func duration(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60)h " + String(format: "%02dm", m % 60)
    }

    /// "+1h 12m", "−20m".
    static func delta(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        let sign = m < 0 ? "\u{2212}" : "+"
        let a = abs(m)
        return a >= 60 ? "\(sign)\(a / 60)h \(a % 60)m" : "\(sign)\(a)m"
    }
}
