import SwiftUI

public struct BTModule: ToolModule {
    public let id = "bt"
    public let name = "BT"
    public let symbol = "bubble.left.and.bubble.right"
    public let tools: [ToolDefinition] = []
    public let snapshot: String? = nil
    private let chat: ChatModel

    public init(chat: ChatModel = ChatModel()) {
        self.chat = chat
    }

    public var content: AnyView {
        AnyView(ChatView(model: chat))
    }
}
