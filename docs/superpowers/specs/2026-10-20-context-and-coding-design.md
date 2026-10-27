# Context layer and coding tracker design (phases 6 and 7)

Covers phases 6 and 7 of [the monorepo and Mac client plan](../plans/2026-10-19-monorepo-and-mac-client.md). Phases 1 to 5 are done: the Mac app has BT chat, Pomodoro and Calendar, and the server streams chat over `/chat/ws` with client-supplied tools. The Mac sends no tools and no context yet.

Phase 6 lets BT see and use the other modules from the Mac. Phase 7 adds a fourth module that tracks time spent coding in VS Code. The two phases share only the tool contract, which landed first on `feat/context-and-coding` (commit `42e0949`), so they are built in parallel.

## Owner decisions (October 20, 2026)

- A coding session ends after 15 minutes without editor activity, so reading and thinking time between edits counts.
- Phase 7 tracks VS Code on the Mac only. The NixOS host comes later, probably through the server.
- Every tool that changes something waits for the owner to approve it: the three calendar writes and the three Pomodoro controls.

## Shared tool contract (done)

`apple/BTKit/Sources/BTKit/ToolModule.swift`:

- `ToolDefinition` gains `parameters: JSONValue` (a JSON Schema object, defaulting to an empty object schema) and `needsApproval: Bool` (default false).
- `ToolModule` gains `func call(_ name: String, arguments: Data) async throws -> String`. `arguments` is the JSON object the model sent. The return value is prose for the model. A default implementation throws `ToolError.unknownTool`, so modules without tools, such as BT, need nothing.
- `ToolError` has `unknownTool`, `badArguments` and `failed` cases with readable descriptions.
- `JSONValue` is a small `Codable` enum with literal conformances, so schemas read as Swift dictionary literals.

Modules decode `arguments` into their own `Decodable` structs. Tool argument structs use snake_case keys to match the schemas, so decode with `.convertFromSnakeCase` or explicit `CodingKeys`.

## Phase 6: context layer

### Snapshot

Each message carries one context string built from the modules' `snapshot` fragments:

- Fragments are taken in sidebar order, which is the priority order. Nil and empty fragments are skipped.
- The budget is 2000 characters, about 500 tokens at four characters per token. A fragment that would push the total over the budget is dropped, and later, shorter fragments can still fit. No fragment is truncated.
- Fragments are joined with newlines. An empty result sends no `context`.

The builder is a pure function in BTKit with unit tests. The snapshot is built when the message is sent, so it reflects the app at that moment.

### Tools over the socket

- On connecting, `ChatModel` sends `hello{tools}` with every module's tool definitions (`name`, `description`, `parameters`). It sends the list on every connect, since the server keeps it per connection.
- `ServerFrame` gains `tool_call{id, name, args}`. `args` decodes as `JSONValue` and is re-encoded to `Data` for `call`.
- `ClientFrame` gains `hello(tools:)` and `toolResult(id:ok:content:)`.
- `ChatModel` gets the module list from the app after the sidebar is built (a settable `modules` property), so `BTModule` can stay first in the sidebar.
- A `tool_call` for an unknown name gets `tool_result{ok: false}` with the `ToolError` text. A tool that throws gets `ok: false` with the error's description. Success sends `ok: true` with the returned prose.

### Approval cards

A `tool_call` whose definition has `needsApproval` shows a card inline in the conversation, below the streaming reply. The card names the tool in plain words (its description) and lists the arguments as `key: value` lines. Approve runs the tool and sends the result. Deny sends `ok: false` with "The owner declined this action."

The server's client tool timeout goes from 30 to 120 seconds, so the owner has time to read a card. If the owner doesn't answer in time the server moves on with its timeout message. When `done` or `error` ends the turn, any card still waiting is removed and its late answer is never sent. There is no client-side timer.

### Tool implementations

Pomodoro (`focus_*`): `focus_start`, `focus_pause` and `focus_stop` need approval. Each returns the snapshot line after the change, so the model can confirm what happened in one call. `focus_get_status` returns the snapshot. `focus_get_stats` returns minutes focused today and over the past seven days, plus the per-day totals for those seven days. None take arguments.

Calendar (`calendar_*`):

- `calendar_list_events{start, end}` returns one line per occurrence with the fields the definition already promises: id, occurrence start, title, times, calendar, location, whether it repeats and whether it can be edited. It caps the range at 31 days.
- `calendar_create_event{title, start, end?, duration_minutes?, calendar?, location?, notes?}` creates the event on the named writable calendar, or the default one, and returns its line. Without `end` or `duration_minutes`, it lasts an hour.
- `calendar_update_event{id, occurrence_start, span?, title?, start?, end?, location?, notes?}` and `calendar_delete_event{id, occurrence_start, span?}` find the occurrence by identifier plus occurrence start, as AGENTS.md requires, and apply `span` (`this_event` by default, or `future_events`). Read-only calendars and missing events produce a `ToolError` the model can read. The three writes need approval.

Dates are ISO 8601. A time with no offset is local time. Without calendar access, every calendar tool returns an error that says access is off.

### Server

Only `CLIENT_TOOL_TIMEOUT_SECS` changes, to 120. History replay of `context` stays as phase 5 left it: each snapshot reaches its own turn only.

### Tests

BTKit: the snapshot builder (order, budget, skipping a fragment that is too long, empty result), the new frames (encode `hello` and `tool_result`, decode `tool_call`), `ChatModel` with a fake socket (sends `hello` on connect and context with a message, runs a tool and replies, denies, removes a waiting card at `done`, unknown tool), Pomodoro tool calls against the existing test doubles, and calendar argument parsing and line formatting as pure functions. EventKit writes stay a hand check, as in phase 3.

Server: the existing timeout test keeps injecting a short timeout; only the constant changes.

## Phase 7: coding tracker

### Heartbeats

A VS Code extension in `editors/vscode/`, written in plain JavaScript with no dependencies and no build step. It appends one JSON line per heartbeat to `~/.bt/inbox/vscode-<YYYY-MM-DD>.jsonl`:

```json
{"ts": 1792512000.5, "editor": "vscode", "project": "bt-assistant", "language": "swift"}
```

`project` is the workspace folder name and `language` is VS Code's `languageId`. No file paths or file contents leave the editor. The extension sends a heartbeat on text changes, saves and active editor changes, at most once a minute for the same project and language and immediately when either changes. Installation is a symlink into `~/.vscode/extensions`, described in `editors/vscode/README.md`. A `node --test` test covers the throttle and the line format.

### Inbox

The sandboxed app reads `~/.bt/inbox/` through the `com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement with `/.bt/inbox/`. That works with ad-hoc signing for local use and avoids writing into the app's container from VS Code. Inside the sandbox `NSHomeDirectory()` points at the container, so the real home comes from `getpwuid(getuid())`.

Ingest runs at launch and whenever the directory changes (a `DispatchSource` file system watcher on the directory). For each `.jsonl` file it renames the file to `.processing`, parses it line by line, inserts the heartbeats and deletes the file. The extension opens and closes the file on every append, so its next heartbeat creates a fresh file. A leftover `.processing` file from a crash is ingested on the next run. Lines that don't parse, or whose fields are out of range (timestamp in the future or before 2020, project over 200 characters, language over 50), are skipped and logged.

### Storage and sessions

Heartbeats are stored as a SwiftData `CodingHeartbeat` (timestamp, editor, project, language), added to `BTModels.all`. Sessions are computed when read, not stored. A pure sessionizer sorts heartbeats and starts a new session after a gap longer than 15 minutes, or when the project changes. A session lasts from its first heartbeat to its last plus one minute, so a lone heartbeat counts as a minute. Its language is the one with the most heartbeats. A session that crosses midnight counts toward the day it started.

### Pane

A Coding pane with today's total and the current session if one is open, a seven-day bar chart (Swift Charts) stacked by project, and a list of totals by project and by language for today or the past seven days.

### Tools and snapshot

- `coding_get_stats{days?}` (1 to 30, default 7) returns the total, per-day totals, and the top projects and languages for the range.
- `coding_list_sessions{date?}` (an ISO date, default today) returns that day's sessions with start, end, project and language.

Both are read-only. The snapshot is one line, for example `Coding: 2h 10m today, now in bt-assistant (swift).` or `Coding: none today.`

The module sits after Calendar in the sidebar.

### Tests

The sessionizer (gap at exactly 15 minutes and just over, project change, lone heartbeat, crossing midnight), line parsing and validation, ingest against a temporary directory (renames, inserts, deletes, skips bad lines, picks up a leftover `.processing`), the snapshot, both tools, and the extension's throttle under `node --test`.

## Non-goals

- Proactive turns, the Today view and linking focus to events. Phase 8.
- Voice using client tools or context. Phase 9.
- Approval preferences or "always allow".
- Replaying old snapshots into later turns.
- Coding time from NixOS, JetBrains or the terminal.
- Packaging the extension for the Marketplace.

## Plan document updates

When this work lands, mark phases 6 and 7 complete in the monorepo plan's Progress with what was verified, close the two open questions with the owner's answers above, and note the `~/.bt/inbox` entitlement in `apple/README.md`.
