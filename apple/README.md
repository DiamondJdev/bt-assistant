# BT Apple clients

The macOS app has a tool sidebar with BT chat, a Pomodoro timer, Calendar and a coding tracker. Pomodoro, Calendar and Coding work without a server; chat needs the BT server. Voice belongs to a later phase in the [client plan](../docs/superpowers/plans/2026-10-19-monorepo-and-mac-client.md).

Press ⌃⌥Space from any app to bring BT up on Calendar. Press it again while BT's window is in front to hide BT. The shortcut is fixed. If another app already owns it, BT logs the failure and runs without it.

## Run

Requires macOS 14 or later and Xcode with Swift 6 support. Open `BT.xcodeproj`, select `BTMac` and press Run. The project uses ad-hoc signing for local development; distribution signing is not configured.

From the repository root, build and launch with:

```sh
xcodebuild -project apple/BT.xcodeproj -scheme BTMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/bt-macos-build build
open /tmp/bt-macos-build/Build/Products/Debug/BT.app
```

The app is sandboxed. Calendar asks for full calendar access the first time you open it. Pomodoro asks for permission to send notifications the first time a phase starts. It also asks to control Music (Automation) the first time it reads the playing track. The `com.apple.security.scripting-targets` entitlement limits it to Music's playback and library-read access groups. It requests outgoing network access to reach the BT server, and no microphone access yet.

If you denied a prompt, re-enable it under System Settings › Notifications › BT, or under System Settings › Privacy & Security › Automation or Calendars.

## BT chat

Set the server address under BT › Settings (⌘,). Use the HTTPS address from `tailscale serve`, or `http://127.0.0.1:8080` for a local server. There is no default and no token; until an address is set, the pane links to Settings.

The pane lists the 50 most recent conversations from the server, including ones started on the phone, and reloads the list when it opens, after each reply and from the refresh button. Selecting one shows its history. Replies stream over `/chat/ws` and render inline Markdown; replies answered by OpenAI carry a small "Cloud" label. If the connection drops, the next message reconnects.

## Pomodoro

The timer runs 25-minute work blocks, 5-minute short breaks and a 15-minute long break after every fourth block. Durations are set from the toolbar button in the pane. The app stores the time each phase ends, so the timer stays correct across sleep and relaunch. Phases don't advance on their own: a notification fires and the next phase waits for Start. Each completed work block, and any stopped block that ran for at least a minute, is saved as a `FocusSession` in the app's SwiftData store. The pane shows today's total. The menu bar shows the countdown and keeps running after the main window is closed; its menu can start, pause, stop and reopen the window. The now-playing card controls whatever is already playing in Music and never opens Music unless you press Open Music.

## Calendar

The Calendar tool reads and writes your calendars through EventKit, so it shows every calendar Apple Calendar knows about, including school and Google subscriptions. Events on subscribed calendars are read-only. You can grant or revoke access in System Settings under Privacy & Security, Calendars; the Calendar pane links there when access is off.

## Coding

The Coding pane tracks time spent in VS Code on this Mac. Install the heartbeat extension as described in [`editors/vscode/README.md`](../editors/vscode/README.md). It records only the workspace folder name, the language and the time, never file paths or contents.

The extension appends heartbeats to `~/.bt/inbox/`. The app reads that folder at launch and whenever it changes, stores each heartbeat as a `CodingHeartbeat` in SwiftData and deletes the file. The sandbox allows this folder through the `com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement with `/.bt/inbox/`. A session ends after 15 minutes without a heartbeat or when the project changes, so reading and thinking time between edits counts. A session counts toward the day it started.

The pane shows today's total, the open session, a seven-day chart by project, and totals by project and language for today or the past seven days.

## Test

From the repository root:

```sh
swift test --package-path apple/BTKit
```

If the repository is under `~/Documents`, codesigning the test bundle can fail with "resource fork, Finder information, or similar detritus not allowed". Run `xattr -cr apple/BTKit/.build` and try again, or pass `--scratch-path /tmp/btkit-build`.

Tests cover the sidebar, the hotkey decision, the chat wire types and chat model, the Pomodoro state machine, the focus log totals, the Pomodoro module's persistence, notifications, snapshot and tool declarations, and the coding tracker's heartbeat parsing, sessions, inbox ingest, tools and snapshot. They do not launch the app. Test the VS Code extension with `node --test editors/vscode`. `BTKit` targets macOS 14 and iOS 17; there is no iOS app target yet.

## Add a module

Implement `ToolModule` in `BTKit` with a stable unique `id`, display `name`, SF Symbol name, tool definitions, optional snapshot and pane content. Pass the module instances to `ToolSidebar(modules:)`; their array order is the sidebar order, and the first module is selected initially. Keep macOS-only services in `BTMac`.

`ToolDefinition` carries a name and description only. The chat socket can carry client tools, but the Mac offers none yet and sends no argument schemas. Snapshot budgeting, execution routing and external-write approval arrive in Phase 6. BT declares no tools and no snapshot until it has data to expose.
