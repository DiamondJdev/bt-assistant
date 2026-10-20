// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BTKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "BTKit", targets: ["BTKit"])],
    targets: [
        .target(name: "BTKit"),
        .testTarget(name: "BTKitTests", dependencies: ["BTKit"]),
    ]
)
