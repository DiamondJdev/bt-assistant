import BTKit
import SwiftUI

@main
struct BTMacApp: App {
    var body: some Scene {
        WindowGroup {
            ToolSidebar()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)
    }
}
