import Foundation

/// A non-2xx answer from the BT server, with its `detail` when it sent one.
public struct ChatServerError: LocalizedError, Equatable {
    public let status: Int
    public let message: String

    public init(status: Int, body: Data) {
        self.status = status
        // /sessions and /history send FastAPI's {"detail": "..."}.
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        message = json?["detail"] as? String ?? "BT server error (\(status))."
    }

    public var errorDescription: String? { message }
}

public protocol ChatAPI: Sendable {
    func sessions() async throws -> [ChatSessionSummary]
    func history(sessionID: String) async throws -> [ChatTurn]
}

public struct URLSessionChatAPI: ChatAPI {
    private let endpoints: ChatEndpoints

    public init(endpoints: ChatEndpoints) {
        self.endpoints = endpoints
    }

    public func sessions() async throws -> [ChatSessionSummary] {
        try await get(endpoints.sessionsURL)
    }

    public func history(sessionID: String) async throws -> [ChatTurn] {
        try await get(endpoints.historyURL(sessionID: sessionID))
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ChatServerError(status: status, body: data) }
        return try ChatJSON.decoder.decode(T.self, from: data)
    }
}

public protocol ChatSocket: AnyObject, Sendable {
    func send(_ frame: ClientFrame) async throws
    func receive() async throws -> ServerFrame
    func close()
}

public final class URLSessionChatSocket: ChatSocket {
    private let task: URLSessionWebSocketTask

    public init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    public func send(_ frame: ClientFrame) async throws {
        let data = try JSONEncoder().encode(frame)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    public func receive() async throws -> ServerFrame {
        let data: Data
        switch try await task.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return .unknown
        }
        return try ChatJSON.decoder.decode(ServerFrame.self, from: data)
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
