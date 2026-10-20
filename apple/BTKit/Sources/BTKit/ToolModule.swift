import Foundation
import SwiftUI

public struct ToolDefinition: Equatable, Sendable {
    public static let noParameters: JSONValue = ["type": "object", "properties": [:]]

    public let name: String
    public let description: String
    /// JSON Schema object for the arguments, sent to the server in `hello`.
    public let parameters: JSONValue
    /// True for tools that change data, so the owner approves each call first.
    public let needsApproval: Bool

    public init(name: String, description: String, parameters: JSONValue = noParameters, needsApproval: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.needsApproval = needsApproval
    }
}

public enum ToolError: LocalizedError, Equatable {
    case unknownTool(String)
    case badArguments(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name): "No tool named \(name)."
        case .badArguments(let reason): "Bad arguments: \(reason)"
        case .failed(let reason): reason
        }
    }
}

@MainActor
public protocol ToolModule {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    var tools: [ToolDefinition] { get }
    var snapshot: String? { get }
    var content: AnyView { get }
    /// Runs one of `tools` with the JSON object the model sent and returns prose for the model.
    /// Throw `ToolError` for anything the model should read as a failure.
    func call(_ name: String, arguments: Data) async throws -> String
}

extension ToolModule {
    public func call(_ name: String, arguments: Data) async throws -> String {
        throw ToolError.unknownTool(name)
    }
}

/// Any JSON value. Used for tool argument schemas.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

extension JSONValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
