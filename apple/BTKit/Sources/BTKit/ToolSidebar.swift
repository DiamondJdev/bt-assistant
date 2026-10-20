import SwiftUI

public struct ToolSidebar: View {
    @State private var model: ToolSidebarModel

    public init(modules: [any ToolModule] = [BTModule()]) {
        _model = State(initialValue: ToolSidebarModel(modules: modules))
    }

    /// Uses a model the caller owns, so the app can change the selection.
    public init(model: ToolSidebarModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedModuleID) {
                Section("Tools") {
                    ForEach(model.modules, id: \.id) { module in
                        Label(module.name, systemImage: module.symbol)
                            .tag(module.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BT")
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
            .accessibilityIdentifier("tool-sidebar")
        } detail: {
            if let module = model.selectedModule {
                module.content
                    .navigationTitle(module.name)
            } else {
                ContentUnavailableView(
                    "Select a tool",
                    systemImage: "sidebar.left",
                    description: Text("Choose a tool from the sidebar.")
                )
            }
        }
    }
}
