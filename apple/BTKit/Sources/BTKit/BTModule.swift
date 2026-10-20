import SwiftUI

public struct BTModule: ToolModule {
    public let id = "bt"
    public let name = "BT"
    public let symbol = "bubble.left.and.bubble.right"
    public let tools: [ToolDefinition] = []
    public let snapshot: String? = nil

    public init() {}

    public var content: AnyView {
        AnyView(
            ContentUnavailableView(
                "BT",
                systemImage: symbol,
                description: Text("Chat will connect to your BT server in a later phase.")
            )
            .accessibilityIdentifier("bt-placeholder")
        )
    }
}
