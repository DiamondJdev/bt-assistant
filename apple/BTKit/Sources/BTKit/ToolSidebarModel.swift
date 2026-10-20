import Observation

@MainActor
@Observable
public final class ToolSidebarModel {
    public let modules: [any ToolModule]
    public var selectedModuleID: String?

    public init(modules: [any ToolModule]) {
        self.modules = modules
        selectedModuleID = modules.first?.id
    }

    public var selectedModule: (any ToolModule)? {
        modules.first { $0.id == selectedModuleID }
    }
}
