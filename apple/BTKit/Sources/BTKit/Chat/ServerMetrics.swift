import Foundation

public struct ServerMetrics: Codable, Equatable, Sendable {
    public var durationMs: Double?
    public var calls: [ModelCallMetrics]?
    public var toolWaitMs: Double?
    public var historyTurns: Int?
    public var contextChars: Int?

    public init(durationMs: Double? = nil) {
        self.durationMs = durationMs
    }
}

public struct ModelCallMetrics: Codable, Equatable, Sendable, Identifiable {
    public var callId: String?
    public var provider: String?
    public var model: String?
    public var status: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var durationMs: Double?
    public var firstOutputMs: Double?
    public var firstVisibleTextMs: Double?
    public var contextLimit: Int?
    /// The most tokens the server lets this call generate.
    public var outputLimit: Int?
    public var toolWaitMs: Double?

    public var id: String { callId ?? "unavailable" }

    public var observedTokensPerSecond: Double? {
        guard let completionTokens, completionTokens >= 0,
              let durationMs, durationMs.isFinite, durationMs > 0 else { return nil }
        return Double(completionTokens) * 1000 / durationMs
    }

    public var contextPercent: Double? {
        guard let promptTokens, promptTokens >= 0, let contextLimit, contextLimit > 0 else { return nil }
        return Double(promptTokens) / Double(contextLimit) * 100
    }
}
