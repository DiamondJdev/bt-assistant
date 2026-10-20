# Context layer implementation plan (phase 6)

> **For agentic workers:** Use superpowers:test-driven-development for each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac sends module snapshots as context and offers module tools over `/chat/ws`. BT can read and control Pomodoro and Calendar, and every write waits for the owner's approval.

**Spec:** `docs/superpowers/specs/2026-10-20-context-and-coding-design.md`, section "Phase 6". The tool contract (`ToolDefinition.parameters`, `needsApproval`, `ToolModule.call`, `ToolError`, `JSONValue`) is already in `apple/BTKit/Sources/BTKit/ToolModule.swift`. Do not change its shape; phase 7 is built against it in parallel.

**Tech stack:** Swift 6, SwiftUI, Swift Testing, EventKit, SwiftData. Python 3.14 and pytest for the one server change.

## Global constraints

- No new Python or Swift dependencies.
- Swift tests, from the worktree root: `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build-context`. Use this exact scratch path; another agent builds in parallel.
- App build: `xcodebuild -project apple/BT.xcodeproj -scheme BTMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/bt-macos-build-context build`.
- Python tests, from `server/`: `uv sync --python 3.14` once, then `uv run python -m pytest -q`.
- Python files use tabs; Swift files use 4 spaces. Match the surrounding comment density.
- The BTMac Xcode group is not file-system synchronized. New Swift files go in BTKit only.
- Phase 7 also edits `apple/BTMac/BTMacApp.swift`, `apple/README.md` and `BTModels.all`. Keep your edits to those small; do not reformat them.
- Commit after each task: `<type>: <description>`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review focus

1. A `done` frame arrives while an approval card waits: the card disappears and pressing its buttons afterwards sends nothing. Task 3.
2. The socket reconnects after a drop: `hello` is sent again before the next `message`. Task 3.
3. `calendar_update_event` on an occurrence of a repeating event finds the occurrence by identifier plus occurrence start, not by identifier alone. Task 6.
4. A time with no UTC offset (`2026-10-21T15:00:00`) is read as local time. Task 6.
5. A fragment longer than the remaining budget is skipped and a later short fragment still fits. Task 1.

---

### Task 1: Snapshot builder

**Files:** create `apple/BTKit/Sources/BTKit/Chat/ContextSnapshot.swift`; test `apple/BTKit/Tests/BTKitTests/ContextSnapshotTests.swift`.

**Produces:** `func contextSnapshot(_ fragments: [String?], budget: Int = 2000) -> String?`. Joins non-empty fragments with `"\n"` in order, skipping any fragment that would push the joined length over `budget`. Returns nil when nothing fits.

- [ ] Tests: order kept; nil and empty skipped; an oversized fragment skipped while a later short one fits; all nil gives nil; newline separators count toward the budget.
- [ ] Run, watch fail, implement, run, commit.

### Task 2: Wire frames

**Files:** modify `apple/BTKit/Sources/BTKit/Chat/ChatWire.swift`; test `ChatWireTests.swift`.

**Produces:**
- `ServerFrame.toolCall(id: String, name: String, args: JSONValue)`. Missing or non-object `args` decodes as an empty object.
- `ClientFrame.hello(tools: [ToolDefinition])`, encoding `{"type":"hello","tools":[{"name","description","parameters"}]}`. `needsApproval` is not sent.
- `ClientFrame.toolResult(id: String, ok: Bool, content: String)`, encoding `{"type":"tool_result","id","ok","content"}`.
- Update the comment on `ClientFrame`; it says these arrive with phase 6.

- [ ] Tests for each encode and decode, including `args` with nested objects.
- [ ] Run, watch fail, implement, run, commit.

### Task 3: ChatModel routing and approvals

**Files:** modify `apple/BTKit/Sources/BTKit/Chat/ChatModel.swift`; test `ChatModelTests.swift` (extend its fake socket).

**Produces:**
- `public var modules: [any ToolModule] = []`.
- `connectedSocket` sends `.hello(tools:)` with every module's tools right after creating a socket, before anything else.
- `send()` sends `.message(text:context: contextSnapshot(modules.map(\.snapshot)))`.
- `public struct ToolApproval: Identifiable, Equatable { id (the call id), toolName, summary (the definition's description), arguments: [(String, String)] as sorted `key: value` lines }`. Pick an `Equatable`-friendly representation for the argument lines.
- `public private(set) var pendingApprovals: [ToolApproval]`.
- `handle(.toolCall)`: find the module and definition owning `name`. Unknown name: send `toolResult(ok: false, content: ToolError.unknownTool(name).localizedDescription)`. `needsApproval`: append a `ToolApproval` and keep the raw args for later. Otherwise run it now.
- `public func approve(_ id: String) async` runs the call and sends the result; `public func deny(_ id: String) async` sends `ok: false, "The owner declined this action."`. Both do nothing if `id` is no longer pending.
- Running a call: `try await module.call(name, arguments: JSONEncoder().encode(args))`; success sends `ok: true` with the prose, a thrown error sends `ok: false` with `error.localizedDescription`.
- `done`, `error` and `reset()` clear `pendingApprovals`.
- Results go to the socket the call came from; if that socket was dropped, drop the result.

- [ ] Tests: `hello` is the first frame on a new socket and again after a reconnect; message carries the snapshot context, or none when all snapshots are nil; a non-approval call runs and replies `ok: true`; an approval call waits, then approve replies; deny replies `ok: false` with the declined text; `done` clears a waiting card and a later `approve` sends nothing; unknown tool replies `ok: false`; a throwing module replies `ok: false` with its description. Use a small fake `ToolModule` in the test file.
- [ ] Run, watch fail, implement, run, commit.

### Task 4: Approval cards in the chat pane

**Files:** modify `apple/BTKit/Sources/BTKit/Chat/ChatView.swift`.

- [ ] Show each `pendingApprovals` entry below the streaming reply: the summary, the argument lines, and Approve and Deny buttons that call the model. Keep it small and native (a `GroupBox` or similar).
- [ ] Build the package, commit. No test; this is view code.

### Task 5: Pomodoro tools

**Files:** modify `apple/BTKit/Sources/BTKit/Pomodoro/PomodoroModule.swift` and `FocusSession.swift` if `FocusLog` needs a per-day query; test `PomodoroModuleTests.swift`.

- [ ] Mark `focus_start`, `focus_pause` and `focus_stop` with `needsApproval: true`. None take arguments; keep the default schema.
- [ ] Implement `call`: start, pause and stop act and return `snapshot`; `focus_get_status` returns `snapshot`; `focus_get_stats` returns today's and the seven-day totals plus one `Mon 19 Oct: 1h 35m` style line per day, oldest first. Unknown names throw `ToolError.unknownTool`.
- [ ] Tests with the existing fakes (fixed `now`, in-memory container): each tool's effect and returned text, the approval flags, stats lines across a week.
- [ ] Run, watch fail, implement, run, commit.

### Task 6: Calendar tools

**Files:** create `apple/BTKit/Sources/BTKit/Calendar/CalendarTools.swift` for argument structs, date parsing and line formatting; modify `CalendarModule.swift` and `CalendarStore.swift` as needed; test `CalendarToolsTests.swift`.

- [ ] Schemas per the spec, with `required` lists and `additionalProperties: false`. `span` is an enum of `this_event` and `future_events`. The three writes get `needsApproval: true`.
- [ ] `parseToolDate(_ text: String, calendar: Calendar) -> Date?` accepts ISO 8601 with an offset, with `Z`, and with no offset (local). Accept a bare date (`2026-10-21`) as local midnight for `calendar_list_events`.
- [ ] `toolLine(_ item: CalendarEventItem, calendar: Calendar) -> String`: one line with id (the `eventIdentifier`), occurrence start as ISO 8601, title, start and end times, calendar, location if any, "repeats" if recurring, "read-only" if not editable. The model must be able to pass id and occurrence start straight back into update and delete.
- [ ] `call`: guard access first (`ToolError.failed("Calendar access is off. Turn it on in System Settings, Privacy & Security, Calendars.")`). List caps the range at 31 days. Create uses the named writable calendar (case-insensitive title match) or `defaultCalendar`, an hour long unless `end` or `duration_minutes` is given, and returns the new event's line. Update and delete find the `EKEvent` with `store.event(for:)` semantics (identifier plus occurrence start), reject read-only calendars, apply the span, save, then return the updated line (or "Deleted <title> on <date>."). Re-read the event after saving rather than keeping identifiers (see AGENTS.md).
- [ ] Tests for the pure parts: date parsing (offset, Z, local, bare date, garbage), argument decoding for each tool including a bad span, the line format, the 31-day cap. EventKit writes stay a hand check.
- [ ] Run, watch fail, implement, run, commit.

### Task 7: Server timeout, app wiring and docs

**Files:** `server/bt/gateway/chat_ws.py`, `apple/BTMac/BTMacApp.swift`, `apple/README.md`.

- [ ] `CLIENT_TOOL_TIMEOUT_SECS = 120.0`. Run the Python tests.
- [ ] In `BTMacApp.init`, keep a reference to the `ChatModel`, build the sidebar, then set `chat.modules = sidebar.modules`.
- [ ] README: replace the "Mac sends no tools" sentences in "BT chat" and "Add a module" with what now happens (snapshots under a 2000-character budget in sidebar order, tools offered in `hello`, approval cards for writes, the 120-second server timeout).
- [ ] Run all Swift tests and the app build. Commit.
