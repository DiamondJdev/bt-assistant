import SwiftUI

/// The BT server address, shared with the chat pane through `@AppStorage`.
public struct ChatSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress = ""

    public init() {}

    public var body: some View {
        Form {
            TextField("Server address", text: $serverAddress, prompt: Text("https://bt.example.ts.net"))
                .autocorrectionDisabled()
            if ChatEndpoints(serverAddress: serverAddress) == nil {
                Text("Enter a full address starting with https://")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
