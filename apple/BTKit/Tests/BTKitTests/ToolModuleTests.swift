import Foundation
import Testing
@testable import BTKit

@MainActor
struct ToolModuleTests {
    @Test func jsonValueEncodesSchemaLiterals() throws {
        let schema: JSONValue = [
            "type": "object",
            "properties": ["minutes": ["type": "integer", "minimum": 1]],
            "required": ["minutes"],
            "additionalProperties": false,
        ]
        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == schema)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["additionalProperties"] as? Bool == false)
        #expect((object["required"] as? [String]) == ["minutes"])
    }

    @Test func toolDefinitionDefaultsToNoArgumentsAndNoApproval() {
        let tool = ToolDefinition(name: "x_status", description: "Status.")
        #expect(tool.parameters == ToolDefinition.noParameters)
        #expect(!tool.needsApproval)
    }

    @Test func defaultCallRejectsUnknownTool() async {
        await #expect(throws: ToolError.self) {
            _ = try await BTModule().call("nope", arguments: Data("{}".utf8))
        }
    }
}
