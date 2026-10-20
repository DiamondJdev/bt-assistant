import Observation

@MainActor
@Observable
final class ToolSidebarModel {
    let modules: [any ToolModule]
    var selectedModuleID: String?

    init(modules: [any ToolModule]) {
        self.modules = modules
        selectedModuleID = modules.first?.id
    }

    var selectedModule: (any ToolModule)? {
        modules.first { $0.id == selectedModuleID }
    }
}
