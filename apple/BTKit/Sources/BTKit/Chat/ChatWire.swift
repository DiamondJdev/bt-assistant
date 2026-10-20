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
    /// A call to one of the tools offered in `hello`; answer with `ClientFrame.toolResult`.
    case toolCall(id: String, name: String, args: JSONValue)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, text, compute, toolsUsed, message, id, name, args
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
        case "tool_call":
            var args = (try? c.decode(JSONValue.self, forKey: .args)) ?? [:]
            if case .object = args {} else { args = [:] }
            self = .toolCall(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name), args: args)
        default:
            self = .unknown
        }
    }
}

/// A frame to the server. `hello` offers the modules' tools on every connect; the server
/// never sends `tool_call` to a client that offered none.
public enum ClientFrame: Encodable, Equatable, Sendable {
    case hello(tools: [ToolDefinition])
    case message(text: String, context: String?)
    case toolResult(id: String, ok: Bool, content: String)

    private enum CodingKeys: String, CodingKey { case type, tools, text, context, id, ok, content }
    private enum ToolKeys: String, CodingKey { case name, description, parameters }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let tools):
            try c.encode("hello", forKey: .type)
            // `needsApproval` stays on the Mac.
            var list = c.nestedUnkeyedContainer(forKey: .tools)
            for tool in tools {
                var t = list.nestedContainer(keyedBy: ToolKeys.self)
                try t.encode(tool.name, forKey: .name)
                try t.encode(tool.description, forKey: .description)
                try t.encode(tool.parameters, forKey: .parameters)
            }
        case .message(let text, let context):
            try c.encode("message", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(context, forKey: .context)
        case .toolResult(let id, let ok, let content):
            try c.encode("tool_result", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(ok, forKey: .ok)
            try c.encode(content, forKey: .content)
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
