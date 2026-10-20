# Monorepo and macOS client plan

Goal: one repository for BT's backend, a native macOS app that is the home for all of the owner's productivity tools (BT, Pomodoro, calendar, coding tracker), and later an iOS app.

The app is a home for tools, and BT is one of them. The tool sidebar is the main view; BT opens as a pane and can see what the other tools know. Each tool works on its own before BT is connected. The app replaces Apple Calendar's interface, but events stay in EventKit so they keep syncing to Google and the owner's phone.

## Layout

```
bt-assistant/
  server/                 Python backend: bt/, tests/, nix/, pyproject.toml, uv.lock
  apple/
    BTKit/                Swift package shared by macOS and iOS: protocol types,
                          ChatSocket, ToolModule, context layer. Tested with `swift test`.
    BT.xcodeproj          thin app targets only
    BTMac/                MenuBarExtra, global hotkey, inbox watcher, Mac-only UI
  editors/vscode/         coding heartbeat extension
  docs/
```

Most Swift code goes in `BTKit` so the iOS app is mostly a new target, and so `.pbxproj` changes stay small. No project generator. The browser client stays in `server/bt/client/` until the Mac app covers what it does, then it is deleted. The wire protocol is defined twice, as Pydantic models and as matching `Codable` structs; shared schema codegen is not worth it for one owner.

## What the backend already covers

- Runs on a private NixOS host over Tailscale, with Ollama Qwen3 and optional OpenAI escalation. The tailnet is the access boundary, so the app needs no token.
- `OriginMiddleware` accepts requests with no `Origin` header, which is what a native client sends.
- History lives in SQLite on the server (`/sessions`, `/history`). The app only caches it.
- `turn_note` already carries per-turn facts on the latest user message so the system prompt stays cacheable. The app's context snapshot goes there.
- Server tools are declared with `@tool` and rendered as OpenAI JSON.

Gaps: text chat is `POST /chat` with no streaming, and there is no way for a client to supply tools. Phase 5 adds both.

Constraints for tool design:

- OpenAI-style function names must match `^[a-zA-Z0-9_-]+$`. Use `calendar_list_events`, not `calendar.list_events`.
- Qwen3 rarely chains a second tool call, so each tool returns everything an answer needs.
- Voice uses a separate Pipecat path. Client tools and snapshots reach text first; voice needs its own wiring.

## Phases

0. Repository restructure. Move the backend into `server/`, add Swift and editor ignores, update README, AGENTS.md and DEPLOYMENT.md. The NixOS host module's working directory becomes `<checkout>/server` in the same deploy.
1. App shell and `ToolModule` protocol. A tool sidebar in BTKit with BT as one entry. Every module declares its tools and snapshot fragment from the start, even though nothing reads them until phase 6.
2. Pomodoro. Menu bar countdown, `phase` and `endsAt` stored rather than ticked, local notifications, `FocusSession` logging, `focus_*` tools.
3. Calendar. Permission flow, day, week and month views, create and edit sheets, recurring edits (`EKSpan.thisEvent` and `.futureEvents`), live refresh on `.EKEventStoreChanged`, `calendar_*` tools. Test recurring edits against real class events early.
4. Global hotkey.
5. BT chat. Backend `/chat/ws` using the same conversation lease as `/chat`. Client sends `hello{tools}`, `message{text, context}` and `tool_result{id, ok, content}`. Server sends `delta`, `tool_call{id, name, args}`, `done{compute}` and `error`. Stream from Ollama, store each snapshot in a nullable `context` column on turns, and time out unanswered client tool calls. Then the chat pane: conversation list, streaming replies, SwiftData cache, server URL setting. This backend work touches no Swift and can run alongside phases 1 to 4.
6. Context layer. Snapshot fragments with priorities under a token budget of about 500 tokens, tool routing over the socket, approve or deny cards before any tool that changes data outside the app.
7. Coding tracker. VS Code extension, `inbox/*.jsonl` watcher, sessionizer, Swift Charts stats, `coding_*` tools.
8. Today view and events. Proactive event turns with a per-hour cap and quiet hours, start focus from an event, auto-tagging.
9. Voice in the Mac client over the existing `/voice/ws` wire format, then delete the browser client.

## Progress

Phase 1 is complete as of October 20, 2026. `apple/BT.xcodeproj` runs the thin macOS app; `apple/BTKit` owns the tool sidebar, `ToolModule` contract and BT placeholder. Modules declare tool metadata and an optional snapshot. Argument schemas, execution and context budgeting remain in phases 5 and 6.

Verification: six package tests pass, Debug and universal Release builds succeed, and the running macOS app shows the selected BT pane and preserves selection when the sidebar is hidden and shown. Signing is ad-hoc for local development. No server connection or iOS app has been implemented.

Next: Phase 2, Pomodoro. See [the Apple client README](../../../apple/README.md) for build and test commands.

## Open questions

- Coding idle threshold: 5 minutes, or longer to count reading time?
- Track NixOS coding time in v1, or later?
