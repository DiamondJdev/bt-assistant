import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
public final class CodingModule: ToolModule {
    public let id = "coding"
    public let name = "Coding"
    public let symbol = "chevron.left.forwardslash.chevron.right"
    public let tools: [ToolDefinition] = [
        ToolDefinition(
            name: "coding_get_stats",
            description: "Time spent coding in VS Code: the total, per-day totals, and the top projects and languages for the past few days.",
            parameters: [
                "type": "object",
                "properties": [
                    "days": ["type": "integer", "minimum": 1, "maximum": 30, "description": "Number of days ending today. Defaults to 7."],
                ],
                "additionalProperties": false,
            ]
        ),
        ToolDefinition(
            name: "coding_list_sessions",
            description: "Coding sessions on one day, each with its start, end, project and language.",
            parameters: [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "Local date as YYYY-MM-DD. Defaults to today."],
                ],
                "additionalProperties": false,
            ]
        ),
    ]

    /// Bumped after each ingest that stored heartbeats; views read it to refresh.
    public private(set) var changeToken = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let inbox: CodingInbox
    @ObservationIgnored let now: @Sendable () -> Date

    public init(
        modelContext: ModelContext,
        inboxDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        context = modelContext
        self.now = now
        inbox = CodingInbox(directory: inboxDirectory ?? CodingInbox.defaultDirectory(), context: modelContext, now: now)
        inbox.onIngest = { [weak self] in self?.changeToken += 1 }
    }

    /// Ingests what is waiting in the inbox, then watches it for new heartbeats.
    public func startWatching() {
        inbox.startWatching()
    }

    // MARK: Reading

    /// Sessions that started in `[from, to)`.
    func sessions(from: Date, to: Date) -> [CodingSession] {
        _ = changeToken
        // ponytail: looks back one day for sessions running into the range; a session over 24h would be cut.
        let lookback = from - 24 * 60 * 60
        let descriptor = FetchDescriptor<CodingHeartbeat>(
            predicate: #Predicate { $0.timestamp >= lookback && $0.timestamp < to }
        )
        let beats = ((try? context.fetch(descriptor)) ?? []).map(\.beat)
        return sessionize(beats).filter { $0.start >= from }
    }

    func sessions(on day: Date, calendar: Calendar = .current) -> [CodingSession] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return sessions(from: interval.start, to: interval.end)
    }

    func stats(days: Int, calendar: Calendar = .current) -> CodingStats {
        let now = now()
        let first = codingDays(days, endingOn: now, calendar: calendar).first ?? calendar.startOfDay(for: now)
        let end = calendar.dateInterval(of: .day, for: now)?.end ?? now
        return codingStats(sessions(from: first, to: end), days: days, endingOn: now, calendar: calendar)
    }

    /// The latest session today if it ended within the idle cutoff.
    var openSession: CodingSession? {
        let now = now()
        guard let last = sessions(on: now).last, now.timeIntervalSince(last.end) <= codingIdleCutoff else { return nil }
        return last
    }

    public var snapshot: String? {
        let total = stats(days: 1).total
        let open = openSession
        guard total > 0 || open != nil else { return "Coding: none today." }
        let today = "Coding: \(PomodoroModule.format(total)) today"
        guard let open else { return today + "." }
        return today + ", now in \(open.project) (\(open.language))."
    }

    public var content: AnyView {
        AnyView(EmptyView())
    }

    // MARK: Tools

    private struct StatsArguments: Decodable {
        var days: Int?
    }

    private struct SessionsArguments: Decodable {
        var date: String?
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        switch name {
        case "coding_get_stats":
            let days = try decode(StatsArguments.self, arguments).days ?? 7
            guard (1...30).contains(days) else { throw ToolError.badArguments("days must be from 1 to 30.") }
            return describeStats(days: days)
        case "coding_list_sessions":
            let date = try decode(SessionsArguments.self, arguments).date
            return try describeSessions(on: date.map(parseDay) ?? now())
        default:
            throw ToolError.unknownTool(name)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ToolError.badArguments("expected a JSON object matching the tool's schema.")
        }
    }

    private func describeStats(days: Int) -> String {
        let stats = stats(days: days)
        let range = days == 1 ? "today" : "over the past \(days) days"
        let perDay = stats.perDay.map { "\(Self.dayFormatter.string(from: $0.day)) \(PomodoroModule.format($0.seconds))" }
        var lines = [
            "Coding \(range): \(PomodoroModule.format(stats.total)).",
            "Per day: \(perDay.joined(separator: ", ")).",
        ]
        if !stats.byProject.isEmpty {
            lines.append("Top projects: \(Self.top(stats.byProject)).")
            lines.append("Top languages: \(Self.top(stats.byLanguage)).")
        }
        return lines.joined(separator: "\n")
    }

    private func describeSessions(on day: Date) throws -> String {
        let label = Self.dayFormatter.string(from: day)
        let sessions = sessions(on: day)
        guard !sessions.isEmpty else { return "No coding sessions on \(label)." }
        let lines = sessions.map { session in
            let start = Self.timeFormatter.string(from: session.start)
            let end = Self.timeFormatter.string(from: session.end)
            return "\(start) to \(end), \(session.project) (\(session.language)), \(PomodoroModule.format(session.duration))"
        }
        return (["Coding sessions on \(label):"] + lines).joined(separator: "\n")
    }

    private func parseDay(_ text: String) throws -> Date {
        // Round-tripping rejects impossible dates such as 2026-02-30.
        guard let date = Self.dayFormatter.date(from: text), Self.dayFormatter.string(from: date) == text else {
            throw ToolError.badArguments("date must be a local date as YYYY-MM-DD.")
        }
        return date
    }

    private static func top(_ totals: [CodingTotal]) -> String {
        totals.prefix(5).map { "\($0.name) \(PomodoroModule.format($0.seconds))" }.joined(separator: ", ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
