# BT Apple clients

Phase 1 provides a native macOS window with a tool sidebar and a BT placeholder. It works without a server. Chat, Pomodoro, calendar and voice belong to later phases in the [client plan](../docs/superpowers/plans/2026-10-19-monorepo-and-mac-client.md).

## Run

Requires macOS 14 or later and Xcode with Swift 6 support. Open `BT.xcodeproj`, select `BTMac` and press Run. The project uses ad-hoc signing for local development; distribution signing is not configured.

From the repository root, build and launch with:

```sh
xcodebuild -project apple/BT.xcodeproj -scheme BTMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/bt-macos-build build
open /tmp/bt-macos-build/Build/Products/Debug/BT.app
```

The app is sandboxed. It requests no calendar, microphone or network access in this phase.

## Test

From the repository root:

```sh
swift test --package-path apple/BTKit
```

Tests cover initial selection, switching modules, missing selections and BT's empty tool/context declarations. They do not launch the app. `BTKit` targets macOS 14 and iOS 17; there is no iOS app target yet.

## Add a module

Implement `ToolModule` in `BTKit` with a stable unique `id`, display `name`, SF Symbol name, tool definitions, optional snapshot and pane content. Pass the module instances to `ToolSidebar(modules:)`; their array order is the sidebar order, and the first module is selected initially. Keep macOS-only services in `BTMac`.

`ToolDefinition` carries a name and description only. Tool argument schemas and the socket protocol arrive with chat in Phase 5. Snapshot budgeting, execution routing and external-write approval arrive in Phase 6. BT declares no tools and no snapshot until it has data to expose.
