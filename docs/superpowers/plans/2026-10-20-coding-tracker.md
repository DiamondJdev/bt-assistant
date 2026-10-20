# Coding tracker implementation plan (phase 7)

> **For agentic workers:** Use superpowers:test-driven-development for each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VS Code on the Mac writes heartbeats to `~/.bt/inbox/`. The app ingests them, turns them into sessions with a 15-minute idle cutoff, shows stats in a Coding pane, and offers read-only `coding_*` tools and a snapshot.

**Spec:** `docs/superpowers/specs/2026-10-20-context-and-coding-design.md`, section "Phase 7". Implement the module against the tool contract in `apple/BTKit/Sources/BTKit/ToolModule.swift` (`ToolDefinition(name:description:parameters:)`, `call(_:arguments:)`, `ToolError`, `JSONValue`). Do not change that file; phase 6 is built against it in parallel and wires tools into chat.

**Tech stack:** Swift 6, SwiftUI, Swift Charts, SwiftData, Swift Testing, `DispatchSource`. Plain JavaScript and `node --test` for the extension.

## Global constraints

- No new dependencies anywhere. The extension has no `node_modules` and no build step.
- Swift tests, from the worktree root: `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build-coding`. Use this exact scratch path; another agent builds in parallel.
- App build: `xcodebuild -project apple/BT.xcodeproj -scheme BTMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/bt-macos-build-coding build`.
- Swift files use 4 spaces; JavaScript uses tabs, like `server/bt/client/`. Match the surrounding comment density.
- The BTMac Xcode group is not file-system synchronized. New Swift files go in `apple/BTKit/Sources/BTKit/Coding/`.
- Phase 6 also edits `apple/BTMac/BTMacApp.swift` and `apple/README.md`. Keep your edits to those small; do not reformat them.
- Idle cutoff is 15 minutes; heartbeat throttle is 60 seconds. Constants, not settings.
- Commit after each task: `<type>: <description>`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review focus

1. Two heartbeats exactly 15 minutes apart stay in one session; 15 minutes and one second apart split. Task 3.
2. The extension appends while the app ingests: no heartbeat is lost or read twice (rename first, then read). Task 4.
3. Inside the sandbox the inbox path resolves to the real `~/.bt/inbox`, not the container. Task 4.
4. A malformed line in the middle of a file skips only that line. Task 2.
5. No file paths or contents appear in a heartbeat line. Task 1.

---

### Task 1: VS Code extension

**Files:** create `editors/vscode/package.json`, `editors/vscode/extension.js`, `editors/vscode/heartbeat.js`, `editors/vscode/heartbeat.test.mjs`, `editors/vscode/README.md`.

- [ ] `heartbeat.js` (CommonJS, no `vscode` import, so tests run under plain node): `heartbeatLine({ts, project, language})` returns the JSON line with `editor: "vscode"` and a trailing newline; `createThrottle(intervalMs = 60000)` returns `shouldSend(project, language, nowMs)`, true when the pair changed or the interval passed since the last send; `inboxFile(home, date)` returns `<home>/.bt/inbox/vscode-YYYY-MM-DD.jsonl` using the local date.
- [ ] `heartbeat.test.mjs` with `node:test`: the line has exactly the four keys; throttle allows the first beat, blocks a repeat inside a minute, allows a changed language immediately, allows after a minute; file name uses the local date.
- [ ] `extension.js`: on `onDidChangeTextDocument`, `onDidSaveTextDocument` and `onDidChangeActiveTextEditor`, for documents with `uri.scheme === "file"` inside a workspace folder, use the folder name as `project` and `languageId` as `language`, ask the throttle (saves always send), then `fs.mkdirSync(dir, {recursive: true})` and `fs.appendFileSync`. Swallow and log write errors to an output channel; never throw into VS Code.
- [ ] `package.json`: `name: "bt-heartbeat"`, `publisher: "diamondjdev"`, `main: "extension.js"`, `activationEvents: ["onStartupFinished"]`, an `engines.vscode` range, `"scripts": {"test": "node --test"}`.
- [ ] README: install with `ln -s "$PWD/editors/vscode" ~/.vscode/extensions/diamondjdev.bt-heartbeat-0.0.1` and reload VS Code; what is recorded and what is not.
- [ ] Run `node --test editors/vscode`, watch fail, implement, run, commit.

### Task 2: Heartbeat parsing and storage

**Files:** create `Coding/CodingHeartbeat.swift`; modify `Pomodoro/FocusSession.swift` (`BTModels.all` only); test `CodingHeartbeatTests.swift`.

- [ ] `@Model final class CodingHeartbeat { timestamp: Date, editor: String, project: String, language: String }` with defaults, CloudKit-compatible like `FocusSession`. Add it to `BTModels.all`.
- [ ] `struct Heartbeat: Equatable, Sendable { timestamp, editor, project, language }` and `func parseHeartbeats(_ text: String, now: Date) -> (beats: [Heartbeat], skipped: Int)`. Reject lines that don't decode, timestamps before 2020-01-01 or more than 5 minutes in the future, empty or over-200-character projects, and empty or over-50-character languages.
- [ ] Tests: good lines, a bad line in the middle, each validation rule, a trailing newline and blank lines.
- [ ] Run, watch fail, implement, run, commit.

### Task 3: Sessionizer and stats

**Files:** create `Coding/CodingSessions.swift`; test `CodingSessionsTests.swift`.

- [ ] `struct CodingSession: Equatable { start, end, project, language }` with `duration`. `func sessionize(_ beats: [Heartbeat], idle: TimeInterval = 15 * 60) -> [CodingSession]`: sorts, splits on a gap over `idle` or a project change, ends each session at its last beat plus 60 seconds, picks the most frequent language (ties go to the latest).
- [ ] `struct CodingStats { total, perDay: [(day: Date, seconds: TimeInterval)], byProject, byLanguage }` (sorted descending) and `func codingStats(_ sessions: [CodingSession], days: Int, endingOn: Date, calendar: Calendar) -> CodingStats`. A session counts toward the day it started. Pick `Equatable` representations that are easy to test.
- [ ] Tests: the 15-minute boundary both ways, project change, lone beat is one minute, unsorted input, language majority, midnight crossing, stats grouping across a week.
- [ ] Run, watch fail, implement, run, commit.

### Task 4: Inbox ingest and watcher

**Files:** create `Coding/CodingInbox.swift`; test `CodingInboxTests.swift`.

- [ ] `static func defaultDirectory() -> URL` from `getpwuid(getuid())` plus `.bt/inbox`.
- [ ] `@MainActor final class CodingInbox(directory: URL, context: ModelContext, now: @escaping @Sendable () -> Date)` with `func ingest() -> Int` (beats inserted): create the directory if missing; for each `*.jsonl`, rename to `*.processing`; then for each `*.processing` (including leftovers), read, parse, insert, save, delete. Log skipped lines with `os.Logger`. A file that fails to read stays for the next run.
- [ ] `func startWatching()`: a `DispatchSource.makeFileSystemObjectSource` on the directory for `.write`, calling `ingest()` on the main actor. `ingest()` once at start.
- [ ] Tests with a temporary directory and an in-memory container: ingests and deletes, skips bad lines, picks up a leftover `.processing`, leaves non-`.jsonl` files alone, a second `ingest()` inserts nothing.
- [ ] Run, watch fail, implement, run, commit.

### Task 5: Coding module

**Files:** create `Coding/CodingModule.swift`; test `CodingModuleTests.swift`.

- [ ] `@MainActor @Observable public final class CodingModule: ToolModule`, `id "coding"`, `name "Coding"`, symbol `chevron.left.forwardslash.chevron.right`. Init takes `modelContext`, an optional inbox directory (default `CodingInbox.defaultDirectory()`), and `now`.
- [ ] Tools per the spec with schemas: `coding_get_stats{days?}` (integer 1 to 30), `coding_list_sessions{date?}` (`YYYY-MM-DD`, local). Read-only. Out-of-range or malformed arguments throw `ToolError.badArguments`.
- [ ] `snapshot`: `Coding: none today.`, `Coding: 2h 10m today.`, or `Coding: 2h 10m today, now in bt-assistant (swift).` when the latest session ended within the idle cutoff of `now`. Reuse `PomodoroModule.format` for durations.
- [ ] Tests: tool declarations and name pattern, each tool's text with seeded heartbeats, bad arguments, each snapshot form.
- [ ] Run, watch fail, implement, run, commit.

### Task 6: Coding pane

**Files:** create `Coding/CodingView.swift`.

- [ ] Today's total and the open session, a seven-day `Chart` of `BarMark`s stacked by project, and a Today or 7 Days picker over project and language totals. Refresh when the inbox ingests (the module can expose a change counter the view reads, like `CalendarStore.changeToken`).
- [ ] Build the package, commit. No test; this is view code.

### Task 7: App wiring and docs

**Files:** `apple/BTMac/BTMac.entitlements`, `apple/BTMac/BTMacApp.swift`, `apple/README.md`, `AGENTS.md`.

- [ ] Entitlement `com.apple.security.temporary-exception.files.home-relative-path.read-write` with the array `["/.bt/inbox/"]`.
- [ ] `BTMacApp`: create `CodingModule(modelContext: container.mainContext)`, start its watcher, and add it to the sidebar after Calendar.
- [ ] README: a "Coding" section (install the extension, what is recorded, the 15-minute cutoff, the inbox path and entitlement) and update the test coverage paragraph.
- [ ] AGENTS.md: `editors/` now holds the VS Code heartbeat extension; test it with `node --test editors/vscode`.
- [ ] Run all Swift tests, the extension tests and the app build. Launch the built app once if you can and confirm the Coding pane appears; say so if you could not. Commit.
