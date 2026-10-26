import Foundation
import OSLog

public enum BTPerformance {
    public enum Operation: String, Codable, Sendable {
        case decode, frameHandling, messageTransform, markdown, scroll, history, toolExecution, approvalWait
    }

    public static func measure<Value>(_ operation: Operation, _ body: () throws -> Value) rethrows -> Value {
        #if BT_DIAGNOSTICS
        let recorder = DiagnosticsRecorder.shared
        guard recorder.enabled else { return try body() }
        let start = ProcessInfo.processInfo.systemUptime
        let interval = recorder.tracesEnabled ? signposter.beginInterval("Client work", "\(operation.rawValue, privacy: .public)") : nil
        defer {
            if let interval { signposter.endInterval("Client work", interval) }
            recorder.sample(operation, milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        #endif
        return try body()
    }

    #if BT_DIAGNOSTICS
    private static let signposter = OSSignposter(subsystem: "com.diamondjdev.bt", category: "performance")
    #endif
}

#if BT_DIAGNOSTICS
public enum DiagnosticEventKind: String, Codable, Sendable {
    case send, connected, firstText, serverMetrics, completed, failed, disconnected, cancelled, approvalRequested, approvalResolved, toolStarted, toolFinished
}

public enum DiagnosticTurnStatus: String, Codable, Sendable {
    case running, completed, failed, disconnected, cancelled
}

public struct DiagnosticEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: DiagnosticEventKind
    public let turnID: String
}

public struct DiagnosticTurn: Codable, Identifiable, Sendable {
    public var id: String
    public var status: DiagnosticTurnStatus = .running
    public var elapsedMs: Double = 0
    public var firstTextMs: Double?
    public var chunks: Int = 0
    public var contextChars: Int = 0
    public var omittedSnapshots: Int = 0
    public var server: ServerMetrics?
}

public struct DiagnosticPerformance: Codable, Sendable {
    public let operation: BTPerformance.Operation
    public let count: Int
    public let latestMs: Double
    public let p95Ms: Double
    public let maximumMs: Double
}

public struct DiagnosticSnapshot: Codable, Sendable {
    public var events: [DiagnosticEvent]
    public var turns: [DiagnosticTurn]
    public var performance: [DiagnosticPerformance]
}

public final class DiagnosticsRecorder: @unchecked Sendable {
    public static let shared = DiagnosticsRecorder()
    private static let chatLog = Logger(subsystem: "com.diamondjdev.bt", category: "chat")
    private static let toolsLog = Logger(subsystem: "com.diamondjdev.bt", category: "tools")
    private static let transportLog = Logger(subsystem: "com.diamondjdev.bt", category: "transport")
    private static let contextLog = Logger(subsystem: "com.diamondjdev.bt", category: "context")
    private let lock = NSLock()
    private var capturing = true
    private var tracing = false
    private var events: [DiagnosticEvent] = []
    private var turns: [DiagnosticTurn] = []
    private var starts: [String: Double] = [:]
    private var samples: [BTPerformance.Operation: [Double]] = [:]
    private let eventLimit: Int
    private let turnLimit: Int

    public init(eventLimit: Int = 500, turnLimit: Int = 50) {
        self.eventLimit = max(1, eventLimit)
        self.turnLimit = max(1, turnLimit)
    }

    public var enabled: Bool {
        get { lock.withLock { capturing } }
        set {
            lock.withLock {
                if !newValue {
                    let now = ProcessInfo.processInfo.systemUptime
                    for index in turns.indices where turns[index].status == .running {
                        turns[index].status = .cancelled
                        turns[index].elapsedMs = (now - (starts[turns[index].id] ?? now)) * 1000
                    }
                    starts.removeAll()
                }
                capturing = newValue
            }
        }
    }

    public var tracesEnabled: Bool {
        get { lock.withLock { tracing } }
        set { lock.withLock { tracing = newValue } }
    }

    public func begin(turnID: String, contextChars: Int = 0, omittedSnapshots: Int = 0) {
        lock.withLock {
            guard capturing else { return }
            starts[turnID] = ProcessInfo.processInfo.systemUptime
            turns.append(DiagnosticTurn(id: turnID, contextChars: contextChars, omittedSnapshots: omittedSnapshots))
            if turns.count > turnLimit {
                starts.removeValue(forKey: turns.removeFirst().id)
            }
            append(.send, turnID: turnID)
        }
    }

    public func event(_ kind: DiagnosticEventKind, turnID: String) {
        lock.withLock {
            guard capturing, let start = starts[turnID], let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
            if kind == .firstText {
                turns[index].chunks += 1
                guard turns[index].firstTextMs == nil else { return }
                turns[index].firstTextMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
            }
            append(kind, turnID: turnID)
        }
    }

    public func update(turnID: String, metrics: ServerMetrics) {
        lock.withLock {
            guard capturing, starts[turnID] != nil, let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
            var bounded = metrics
            bounded.calls = metrics.calls.map { Array($0.prefix(32)) }
            turns[index].server = bounded
            append(.serverMetrics, turnID: turnID)
        }
    }

    public func finish(turnID: String, status: DiagnosticTurnStatus) {
        lock.withLock {
            guard capturing, let start = starts.removeValue(forKey: turnID), let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
            turns[index].elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1000
            turns[index].status = status
            append(DiagnosticEventKind(rawValue: status.rawValue) ?? .failed, turnID: turnID)
        }
    }

    public func sample(_ operation: BTPerformance.Operation, milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        lock.withLock {
            guard capturing else { return }
            samples[operation, default: []].append(milliseconds)
            if samples[operation, default: []].count > 128 { samples[operation]?.removeFirst() }
        }
    }

    public func snapshot() -> DiagnosticSnapshot {
        lock.withLock {
            var currentTurns = turns
            let now = ProcessInfo.processInfo.systemUptime
            for index in currentTurns.indices {
                if let start = starts[currentTurns[index].id] { currentTurns[index].elapsedMs = (now - start) * 1000 }
            }
            let performance = samples.map { operation, values in
                let sorted = values.sorted()
                return DiagnosticPerformance(operation: operation, count: values.count, latestMs: values.last ?? 0,
                    p95Ms: sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)], maximumMs: sorted.last ?? 0)
            }.sorted { $0.operation.rawValue < $1.operation.rawValue }
            return DiagnosticSnapshot(events: events, turns: currentTurns, performance: performance)
        }
    }

    public func clear() {
        lock.withLock {
            events.removeAll()
            turns.removeAll()
            starts.removeAll()
            samples.removeAll()
        }
    }

    public func export() throws -> Data {
        let snapshot = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var lines = [try encoder.encode(BuildMetadata.current)]
        lines += try snapshot.turns.map { try encoder.encode($0) }
        lines += try snapshot.events.map { try encoder.encode($0) }
        lines += try snapshot.performance.map { try encoder.encode($0) }
        return lines.reduce(into: Data()) { result, line in
            result.append(line)
            result.append(0x0A)
        }
    }

    private func append(_ kind: DiagnosticEventKind, turnID: String) {
        events.append(DiagnosticEvent(id: UUID(), timestamp: Date(), kind: kind, turnID: turnID))
        if events.count > eventLimit { events.removeFirst() }
        let logger: Logger
        switch kind {
        case .connected, .disconnected: logger = Self.transportLog
        case .approvalRequested, .approvalResolved, .toolStarted, .toolFinished: logger = Self.toolsLog
        case .serverMetrics: logger = Self.contextLog
        default: logger = Self.chatLog
        }
        logger.info("event=\(kind.rawValue, privacy: .public) turn=\(turnID, privacy: .public)")
    }
}

public struct BuildMetadata: Encodable, Sendable {
    public let type = "build"
    public let sha: String
    public let mode: String
    public let appVersion: String
    public let osVersion: String
    public let diagnostics = true
    public let captureEnabled: Bool
    public let tracesEnabled: Bool

    public static var current: BuildMetadata {
        BuildMetadata(sha: Bundle.main.object(forInfoDictionaryKey: "BTBuildSHA") as? String ?? "unavailable",
            mode: Bundle.main.object(forInfoDictionaryKey: "BTBuildMode") as? String ?? "debug",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unavailable",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            captureEnabled: DiagnosticsRecorder.shared.enabled, tracesEnabled: DiagnosticsRecorder.shared.tracesEnabled)
    }
}
#endif
