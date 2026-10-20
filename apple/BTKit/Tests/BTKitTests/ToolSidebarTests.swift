import SwiftUI
import Testing
@testable import BTKit

@MainActor
struct ToolSidebarTests {
    @Test func selectsFirstModuleOnLaunch() {
        let model = ToolSidebarModel(modules: [BTModule(), SampleModule()])

        #expect(model.selectedModuleID == "bt")
        #expect(model.selectedModule?.name == "BT")
    }

    @Test func selectionResolvesAnotherModuleAndItsContext() {
        let model = ToolSidebarModel(modules: [BTModule(), SampleModule()])

        model.selectedModuleID = "sample"

        #expect(model.selectedModule?.name == "Sample")
        #expect(model.selectedModule?.snapshot == "Sample is ready")
        #expect(model.selectedModule?.tools == [
            ToolDefinition(name: "sample_status", description: "Read sample status")
        ])
    }

    @Test func clearingSelectionDoesNotResolveAModule() {
        let model = ToolSidebarModel(modules: [BTModule()])

        model.selectedModuleID = nil

        #expect(model.selectedModule == nil)
    }

    @Test func unknownSelectionDoesNotResolveAModule() {
        let model = ToolSidebarModel(modules: [BTModule()])

        model.selectedModuleID = "missing"

        #expect(model.selectedModule == nil)
    }

    @Test func emptySidebarHasNoSelection() {
        let model = ToolSidebarModel(modules: [])

        #expect(model.selectedModuleID == nil)
        #expect(model.selectedModule == nil)
    }

    @Test func btDoesNotAdvertiseUnimplementedToolsOrContext() {
        let module = BTModule()

        #expect(module.id == "bt")
        #expect(module.name == "BT")
        #expect(!module.symbol.isEmpty)
        #expect(module.tools.isEmpty)
        #expect(module.snapshot == nil)
    }
}

@MainActor
private struct SampleModule: ToolModule {
    let id = "sample"
    let name = "Sample"
    let symbol = "square"
    let tools = [ToolDefinition(name: "sample_status", description: "Read sample status")]
    let snapshot: String? = "Sample is ready"

    var content: AnyView { AnyView(Text("Sample")) }
}
