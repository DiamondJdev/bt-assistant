import SwiftUI

public struct ToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
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
}
