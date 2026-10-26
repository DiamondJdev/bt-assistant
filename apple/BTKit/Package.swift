// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BTKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "BTKit", targets: ["BTKit"])],
    targets: [
        .target(name: "BTKit", resources: [.process("Resources")],
                swiftSettings: [.define("BT_DIAGNOSTICS", .when(configuration: .debug))]),
        .testTarget(name: "BTKitTests", dependencies: ["BTKit"],
                    swiftSettings: [.define("BT_DIAGNOSTICS", .when(configuration: .debug))]),
    ]
)
