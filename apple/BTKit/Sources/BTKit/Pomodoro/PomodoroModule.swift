import Foundation
import Observation
import os
import SwiftData
import SwiftUI

@MainActor
@Observable
public final class PomodoroModule: ToolModule {
    public let id = "pomodoro"
    public let name = "Pomodoro"
    public let symbol = "timer"
    public let tools: [ToolDefinition] = [
        ToolDefinition(name: "focus_get_status", description: "Current Pomodoro phase, time remaining, and minutes focused today."),
        ToolDefinition(
            name: "focus_start",
            description: "Start or resume the Pomodoro timer. Without phase it starts the phase that is up next. "
                + "With a different phase it ends the current one and starts that phase.",
            parameters: [
                "type": "object",
                "properties": ["phase": ["type": "string", "enum": ["work", "short_break", "long_break"]]],
                "additionalProperties": false,
            ],
            needsApproval: true
        ),
        ToolDefinition(name: "focus_pause", description: "Pause the running Pomodoro phase.", needsApproval: true),
        ToolDefinition(name: "focus_stop", description: "Stop the Pomodoro timer and log any work time of at least one minute.",
                       needsApproval: true),
        ToolDefinition(name: "focus_get_stats", description: "Minutes focused today and over the past 7 days."),
    ]

    public private(set) var state: PomodoroState {
        didSet { save(state, key: Keys.state) }
    }

    /// Applies to the next phase started; the running phase keeps its `endsAt`.
    public var durations: PomodoroDurations {
        didSet { save(durations, key: Keys.durations) }
    }

    public let nowPlaying: (any NowPlayingSource)?

    @ObservationIgnored private let log: FocusLog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: any PhaseNotifier
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var notifierTask: Task<Void, Never>?

    private enum Keys {
        static let state = "pomodoro.state"
        static let durations = "pomodoro.durations"
    }

    private static let logger = Logger(subsystem: "BTKit", category: "Pomodoro")

    public init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        notifier: any PhaseNotifier = SystemPhaseNotifier(),
        now: @escaping @Sendable () -> Date = Date.init,
        nowPlaying: (any NowPlayingSource)? = nil
    ) {
        log = FocusLog(context: modelContext)
        self.defaults = defaults
        self.notifier = notifier
        self.now = now
        self.nowPlaying = nowPlaying
        state = Self.load(PomodoroState.self, key: Keys.state, from: defaults) ?? .idle
        durations = Self.load(PomodoroDurations.self, key: Keys.durations, from: defaults) ?? PomodoroDurations()
        tick()
    }

    // MARK: Controls

    public func start() {
        if state.isPaused { return resume() }
        guard !state.isRunning else { return }
        state = state.started(at: now(), durations: durations)
        scheduleNotification()
    }

    /// Starts `phase`, ending a different active or waiting phase first.
    public func start(_ phase: PomodoroPhase) {
        if phase != state.phase {
            finish(state.switched(to: phase, at: now()))
            enqueue { await $0.cancelAll() }
        }
        start()
    }

    public func pause() {
        guard state.isRunning else { return }
        state = state.paused(at: now())
        enqueue { await $0.cancelAll() }
    }

    public func resume() {
        guard state.isPaused else { return }
        state = state.resumed(at: now())
        scheduleNotification()
    }

    public func skip() {
        finish(state.skipped(at: now(), durations: durations))
        enqueue { await $0.cancelAll() }
    }

    public func stop() {
        finish(state.stopped(at: now()))
        enqueue { await $0.cancelAll() }
    }

    /// Completes the running phase once its end has passed. Its notification already fired.
    public func tick() {
        guard let endsAt = state.endsAt, now() >= endsAt else { return }
        finish(state.completed(durations: durations))
    }

    // MARK: Reading

    public var todayFocused: TimeInterval {
        log.totalFocused(on: now())
    }

    public func remaining() -> TimeInterval? {
        state.remaining(at: now())
    }

    /// `18:42` while a phase is running or paused, `nil` when idle.
    public var menuBarTitle: String? {
        guard let remaining = remaining() else { return nil }
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Remaining time matches the menu bar to the second, so BT quotes what the owner sees.
    public var snapshot: String? {
        let today = "\(Self.format(todayFocused)) focused today."
        let phase = Self.describe(state.phase)
        guard let left = menuBarTitle else { return "Focus: idle, \(phase) up next, \(today)" }
        let paused = state.isPaused ? " paused" : ""
        return "Focus: \(phase)\(paused), \(left) left, \(today)"
    }

    public var content: AnyView {
        AnyView(PomodoroView(module: self))
    }

    // MARK: Tools

    /// Controls return the snapshot after the change so the model can confirm it in one call.
    public func call(_ name: String, arguments: Data) async throws -> String {
        switch name {
        case "focus_start":
            if let phase = try Self.phaseArgument(arguments) { start(phase) } else { start() }
        case "focus_pause": pause()
        case "focus_stop": stop()
        case "focus_get_status": break
        case "focus_get_stats": return stats()
        default: throw ToolError.unknownTool(name)
        }
        return snapshot ?? ""
    }

    /// Today's and the past seven days' totals, then one `Mon 19 Oct: 1h 35m` line per day, oldest first.
    private func stats() -> String {
        let calendar = Calendar.current
        let today = now()
        let week = log.totalFocused(lastDays: 7, endingOn: today, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM"
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let lines = days.map { "\(formatter.string(from: $0)): \(Self.format(log.totalFocused(on: $0, calendar: calendar)))" }
        let summary = "Focused \(Self.format(todayFocused)) today and \(Self.format(week)) over the past 7 days."
        return ([summary] + lines).joined(separator: "\n")
    }

    private static func phaseArgument(_ arguments: Data) throws -> PomodoroPhase? {
        struct Arguments: Decodable { let phase: String? }
        guard let arguments = try? JSONDecoder().decode(Arguments.self, from: arguments) else {
            throw ToolError.badArguments("expected an object with an optional phase")
        }
        switch arguments.phase {
        case nil: return nil
        case "work": return .work
        case "short_break": return .shortBreak
        case "long_break": return .longBreak
        case let other?: throw ToolError.badArguments("phase must be work, short_break or long_break, not \(other)")
        }
    }

    /// Waits for queued notification work; used by tests.
    func notificationsSettled() async {
        await notifierTask?.value
    }

    static func describe(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .work: "work phase"
        case .shortBreak: "short break"
        case .longBreak: "long break"
        }
    }

    /// `1h 35m`, or `35m` under an hour.
    static func format(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: Private

    private func finish(_ result: (PomodoroState, FocusInterval?)) {
        if let interval = result.1 {
            do {
                try log.record(interval, label: nil)
            } catch {
                Self.logger.error("Could not log focus session: \(error.localizedDescription)")
            }
        }
        state = result.0
    }

    private func scheduleNotification() {
        guard let endsAt = state.endsAt else { return }
        let phase = state.phase
        enqueue { await $0.schedule(phase: phase, at: endsAt) }
    }

    /// Runs notifier calls one after another so a quick pause/resume can't reorder them.
    private func enqueue(_ work: @escaping @Sendable (any PhaseNotifier) async -> Void) {
        let previous = notifierTask
        let notifier = notifier
        notifierTask = Task {
            await previous?.value
            await work(notifier)
        }
    }

    private func save(_ value: some Encodable, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Self.logger.error("Could not save \(key): \(error.localizedDescription)")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
