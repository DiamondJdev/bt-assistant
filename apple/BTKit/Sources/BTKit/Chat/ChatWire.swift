import Foundation

/// Frame and REST shapes for the BT server's `/chat/ws`, `/sessions` and `/history`.
enum ChatJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// A frame from the server. Decode with `ChatJSON.decoder`.
public enum ServerFrame: Decodable, Equatable, Sendable {
    case session(id: String)
    case delta(String)
    case done(text: String, compute: String, toolsUsed: [String])
    case error(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, text, compute, toolsUsed, message
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "session":
            self = .session(id: try c.decode(String.self, forKey: .sessionId))
        case "delta":
            self = .delta(try c.decode(String.self, forKey: .text))
        case "done":
            self = .done(
                text: try c.decode(String.self, forKey: .text),
                compute: try c.decode(String.self, forKey: .compute),
                toolsUsed: try c.decode([String].self, forKey: .toolsUsed)
            )
        case "error":
            self = .error(try c.decode(String.self, forKey: .message))
        default:
            self = .unknown
        }
    }
}

/// A frame to the server. `hello` and `tool_result` arrive with phase 6 tools; the server
/// never sends `tool_call` to a client that offered none.
public enum ClientFrame: Encodable, Equatable, Sendable {
    case message(text: String, context: String?)

    private enum CodingKeys: String, CodingKey { case type, text, context }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let text, let context):
            try c.encode("message", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(context, forKey: .context)
        }
    }
}

public struct ChatSessionSummary: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let updatedAt: Double
}

public struct ChatTurn: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let ts: Double
    /// `"user"` or `"bt"`.
    public let role: String
    public let text: String
    public let compute: String?
}

/// URLs for one server address, such as `https://bt.example.ts.net`.
public struct ChatEndpoints: Equatable, Sendable {
    private let base: URLComponents

    /// Nil unless the address is an `http` or `https` URL with a host.
    public init?(serverAddress: String) {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        parts.scheme = scheme
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        parts.query = nil
        parts.fragment = nil
        base = parts
    }

    public var sessionsURL: URL { url(path: "/sessions") }

    public func historyURL(sessionID: String) -> URL {
        url(path: "/history", query: [URLQueryItem(name: "session_id", value: sessionID)])
    }

    public func socketURL(sessionID: String?) -> URL {
        let query = sessionID.map { [URLQueryItem(name: "session_id", value: $0)] } ?? []
        return url(path: "/chat/ws", query: query, scheme: base.scheme == "https" ? "wss" : "ws")
    }

    private func url(path: String, query: [URLQueryItem] = [], scheme: String? = nil) -> URL {
        var parts = base
        parts.path += path
        parts.queryItems = query.isEmpty ? nil : query
        if let scheme { parts.scheme = scheme }
        // The init validated scheme and host, so this always builds.
        return parts.url!
    }
}
