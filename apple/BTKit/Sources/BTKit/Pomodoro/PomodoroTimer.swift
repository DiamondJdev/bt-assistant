import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case work, shortBreak, longBreak
}

public struct PomodoroDurations: Codable, Equatable, Sendable {
    public var work: TimeInterval = 1500
    public var shortBreak: TimeInterval = 300
    public var longBreak: TimeInterval = 900
    public var longBreakEvery: Int = 4

    public init() {}

    /// Missing keys keep their defaults, so adding a field never resets saved durations.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        work = try container.decodeIfPresent(TimeInterval.self, forKey: .work) ?? work
        shortBreak = try container.decodeIfPresent(TimeInterval.self, forKey: .shortBreak) ?? shortBreak
        longBreak = try container.decodeIfPresent(TimeInterval.self, forKey: .longBreak) ?? longBreak
        longBreakEvery = try container.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? longBreakEvery
    }

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

public struct FocusInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
}

/// Timer state stored as `endsAt` (running) or `pausedRemaining` (paused),
/// never as a decrementing counter, so it survives sleep and relaunch.
///
/// While a phase is active, `startedAt` is its effective start: resuming
/// shifts it forward by the paused span, so `startedAt + phaseDuration`
/// is always the scheduled end and elapsed time excludes pauses.
public struct PomodoroState: Codable, Equatable, Sendable {
    public var phase: PomodoroPhase
    public var startedAt: Date?
    public var endsAt: Date?
    public var pausedRemaining: TimeInterval?
    public var phaseDuration: TimeInterval
    public var completedWorkPhases: Int

    static let minimumLoggedWork: TimeInterval = 60

    public static let idle = PomodoroState(
        phase: .work, startedAt: nil, endsAt: nil, pausedRemaining: nil,
        phaseDuration: 0, completedWorkPhases: 0
    )

    public var isRunning: Bool { endsAt != nil }
    public var isPaused: Bool { pausedRemaining != nil }

    public func remaining(at date: Date) -> TimeInterval? {
        if let pausedRemaining { return pausedRemaining }
        return endsAt.map { max(0, $0.timeIntervalSince(date)) }
    }

    public func started(at date: Date, durations: PomodoroDurations) -> PomodoroState {
        if isPaused { return resumed(at: date) }
        guard !isRunning else { return self }
        let duration = durations.duration(of: phase)
        var next = self
        next.startedAt = date
        next.endsAt = date + duration
        next.phaseDuration = duration
        return next
    }

    public func paused(at date: Date) -> PomodoroState {
        guard isRunning, let remaining = remaining(at: date) else { return self }
        var next = self
        next.endsAt = nil
        next.pausedRemaining = remaining
        return next
    }

    public func resumed(at date: Date) -> PomodoroState {
        guard let pausedRemaining else { return self }
        var next = self
        next.pausedRemaining = nil
        next.endsAt = date + pausedRemaining
        next.startedAt = date - (phaseDuration - pausedRemaining)
        return next
    }

    /// The phase reached `endsAt`: log the full work phase and wait at the next phase.
    public func completed(durations: PomodoroDurations) -> (PomodoroState, FocusInterval?) {
        guard let startedAt, isRunning || isPaused else { return (self, nil) }
        let interval = phase == .work
            ? FocusInterval(start: startedAt, end: startedAt + phaseDuration)
            : nil
        return (advanced(durations: durations), interval)
    }

    public func skipped(at date: Date, durations: PomodoroDurations) -> (PomodoroState, FocusInterval?) {
        guard isRunning || isPaused else { return (advanced(durations: durations), nil) }
        return (advanced(durations: durations), partialWork(at: date))
    }

    public func stopped(at date: Date) -> (PomodoroState, FocusInterval?) {
        (.idle, partialWork(at: date))
    }

    /// Ends any active phase and waits at `phase`, keeping the work-phase count toward the long break.
    public func switched(to phase: PomodoroPhase, at date: Date) -> (PomodoroState, FocusInterval?) {
        var next = PomodoroState.idle
        next.phase = phase
        next.completedWorkPhases = completedWorkPhases
        return (next, partialWork(at: date))
    }

    private func partialWork(at date: Date) -> FocusInterval? {
        guard phase == .work, let startedAt, let remaining = remaining(at: date) else { return nil }
        let elapsed = phaseDuration - remaining
        guard elapsed >= Self.minimumLoggedWork else { return nil }
        return FocusInterval(start: startedAt, end: startedAt + elapsed)
    }

    private func advanced(durations: PomodoroDurations) -> PomodoroState {
        var next = PomodoroState.idle
        next.completedWorkPhases = completedWorkPhases
        if phase == .work {
            next.completedWorkPhases += 1
            let every = max(1, durations.longBreakEvery)
            next.phase = next.completedWorkPhases.isMultiple(of: every) ? .longBreak : .shortBreak
        }
        return next
    }
}
