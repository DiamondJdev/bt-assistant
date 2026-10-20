# Global hotkey and BT chat design (phases 4 and 5)

Covers phases 4 and 5 of [the monorepo and Mac client plan](../plans/2026-10-19-monorepo-and-mac-client.md). Phases 1 to 3 are done: the Mac app has a tool sidebar with BT (a placeholder), Pomodoro and Calendar.

## Why

The owner opens Calendar many times a day to check upcoming events or add one, usually from another app. Phase 4 makes that one keystroke.

BT chat on the Mac is secondary. The owner mostly talks to BT from an iPhone, through the browser client. On the Mac they want to read those conversations and, later, let BT use the other modules. The workflow they want to grow into:

1. On the phone: "I need to study for my chemistry test."
2. At the Mac: "Starting now." BT starts a Pomodoro linked to the calendar event.
3. Afterwards the event shows how much of the block was focused time (say 90%).
4. Later: "When are my most productive times?"
5. Eventually: "Start the day", "Help me choose today's work", "Catch me up on X".

Phases 4 and 5 build none of steps 2 to 5. Phase 5 builds the pipe they need: a streaming chat socket on which the client can offer its own tools, and a Mac chat pane that shows every conversation, including ones from the phone. Phase 6 and later make BT call module tools.

## Goals

- ⌃⌥Space toggles BT from anywhere, landing on Calendar.
- The server streams text chat over a WebSocket and supports tools supplied by the client, tested end to end with a fake client.
- The Mac BT pane lists all conversations, shows their history, and streams new replies.

## Non-goals

- BT calling Pomodoro or Calendar tools from the Mac. Phase 6.
- Sending module snapshots as context. The protocol carries them; the Mac sends none until phase 6 budgets them.
- Approve or deny cards. Phase 6.
- A native iOS app. It comes after the Mac app is finished.
- Moving the browser client to the socket. It stays on `POST /chat`.
- An offline cache of conversations. History lives on the server and the Mac is mostly for reading.
- A configurable hotkey.
- Voice in the Mac app. Phase 9.

## Phase 4: global hotkey

The shortcut is fixed at ⌃⌥Space. Spotlight uses ⌘Space, input source switching uses ⌃Space, and several assistant apps take ⌥Space, so ⌃⌥Space is the least likely to collide.

Behavior:

- If BT is the active app and its main window is on screen (open and not minimized), the hotkey hides BT (`NSApp.hide`), whichever tool is showing. macOS returns focus to the previous app.
- Otherwise, including when BT is active with its window closed or only the menu bar menu open, the hotkey selects Calendar in the sidebar, opens the main window if it was closed, and activates BT.

Register the hotkey with Carbon's `RegisterEventHotKey`. It needs no Accessibility permission and no package. The code lives in `apple/BTMac`, since global hotkeys are Mac only. If registration fails because another app owns the combination, log it and carry on; the app works without the hotkey.

The sidebar's selection is currently private `@State` inside `ToolSidebar`. The app needs to set it from outside, so lift the selection (or the `ToolSidebarModel`) up to `BTMacApp` and pass it in. Keep the change small; the existing sidebar tests must still pass.

Test the show-or-hide decision as a small pure function if that falls out naturally. The rest is a hand check: press the hotkey from another app, from BT on Pomodoro, and with the main window closed.

## Phase 5: server

### Endpoint

`/chat/ws`, with an optional `session_id` query parameter. Without one the server creates a session. Mirror `/voice/ws`: accept, then send `session{session_id}` first. An unknown `session_id` gets an `error` and a close. The existing `OriginMiddleware` already admits native clients, which send no `Origin`.

The connection carries many turns. Each turn takes the conversation lease (`store.conversation`) for its own duration, the same lease `/chat` and voice use, so the phone can still post between turns. A busy conversation produces an `error` for that message and the socket stays open.

### Messages

All frames are JSON objects with a `type` field.

Client to server:

- `hello{tools}` is optional and comes before the first message. Each tool is `{name, description, parameters}`, where `parameters` is a JSON Schema object. Names must match `^[a-zA-Z0-9_-]+$` and must not collide with server tools; a bad list gets an `error` and the connection keeps going with no client tools.
- `message{text, context}`. `text` follows the same rules as `ChatRequest.text`. `context` is an optional string, at most 4000 characters.
- `tool_result{id, ok, content}`. `content` is the prose the model will read.

Server to client:

- `session{session_id}`
- `delta{text}` carries reply text as it streams, with `<think>` spans removed even when a tag is split across chunks.
- `tool_call{id, name, args}`, only for client tools. `args` is the parsed JSON object.
- `done{text, compute, tools_used}`. `text` is the final stored reply and replaces whatever deltas the client showed. `tools_used` includes client tools.

Deltas stream from every round of the local model, so text the model writes before a tool call stays visible until `done` replaces the bubble. Once a turn escalates to the cloud, the server sends no more deltas for that turn and the cloud reply arrives whole in `done`. This keeps the frame list unchanged; a reset frame can come later if the jump bothers the owner.
- `error{message}`, with a message suitable for display.

A `message` sent while a turn is running gets an `error`. One turn at a time per socket.

### Streaming and routing

Add a streaming path to `bt/llm/router.py` that keeps the current policy: escalation phrases start on the cloud, a local failure or a degenerate local reply escalates, the tool loop is capped at `MAX_TOOL_ITERATIONS`, and the final forced answer uses `tool_choice="none"`. Tool calls arrive in pieces in a streamed response and must be put back together before dispatch. Keep `respond()` working for `/chat` and voice; sharing code between the two paths is the builder's call.

Server tools dispatch as they do now. A client tool call sends `tool_call` and waits for the matching `tool_result`. After 30 seconds without an answer, or if the result has `ok: false`, the model gets a short prose explanation as the tool result and the turn continues. A `tool_result` with an unknown id is ignored. Client tools only reach the text path; voice is unchanged. Client tools follow `BT_TOOLS` like server tools: with tools off, `hello` is accepted and its tools are ignored.

### Storage

Add a nullable `context` column to `turns`, filled on user turns from `message.context`. Existing databases get it with `ALTER TABLE ... ADD COLUMN` when the column is missing. `Turn` and `/history` gain the field. The context also goes into that turn's `turn_note`, so the system prompt stays stable. Context applies to its own turn only: rebuilding history for later turns does not replay it, so the column is a record for now. Phase 6 can revisit this when real snapshots exist.

The user turn is stored when the message arrives, as `/chat` does. The BT turn is stored at `done`. If the client disconnects mid-turn, cancel the turn and store no BT reply. If the turn fails, send `error` and store no BT reply.

### Tests

Use the FastAPI test client's WebSocket support with a fake model provider, in the style of the existing gateway tests. Cover streaming deltas and `done`, a client tool round trip, a client tool timeout (with a short timeout injected), lease conflict with `/chat`, an unknown session, a bad `hello`, a split `<think>` tag, the context column on a fresh and on an existing database, and a disconnect mid-turn. Pure functions such as think stripping and tool call reassembly can have direct unit tests.

## Phase 5: Mac chat pane

`BTModule` becomes the chat pane, written in BTKit so iOS can reuse it.

- A conversation list from `GET /sessions` (the 50 most recent, labeled by the server), with a new conversation button. It reloads when the pane appears, after each reply, and from a refresh button. There is no live push, so a phone conversation appears on the next reload.
- Selecting a conversation loads `GET /history`, opens `/chat/ws` for that session, and shows the turns.
- A composer that sends `message`, a reply bubble that fills from `delta` and is replaced by `done.text`, and a small marker on replies whose `compute` is `openai`.
- Replies render Markdown through `AttributedString(markdown:)`.
- Errors (`error` frames, a dropped socket, an unreachable server) show inline with a retry. A dropped socket reconnects when the next message is sent.
- The Mac sends `hello` with an empty tool list and no `context` for now.

Wire types are `Codable` structs in BTKit that match the Pydantic models. Use `URLSessionWebSocketTask`, with no packages.

The server URL comes from a Settings window (⌘,) and is stored with `@AppStorage`. There's no default. Until one is set, the pane says so and links to Settings. The deployed server is the HTTPS address from `tailscale serve`, so App Transport Security needs no exceptions; `http://127.0.0.1:8080` also works for local development. The sandboxed app needs the `com.apple.security.network.client` entitlement. There's no token, since the tailnet is the access boundary.

Tests cover the wire types (encoding and decoding each frame) and the pane's state handling with a fake socket: deltas accumulate, `done` replaces them, an error leaves the composer usable.

## Plan document updates

When this work lands, update the monorepo plan:

- Phase 9 no longer deletes the browser client. It stays until a native iOS app replaces it, and the iOS app is a new phase after the Mac app is finished.
- Record the owner's later goals so they aren't lost: link a focus session to a calendar event, show the focused percentage on the event, add a tool that answers "when am I most productive", and add briefings ("Start the day", "Catch me up"). The first two extend phase 8's "start focus from an event"; the rest belong with phases 6 and 8.
- Mark phases 4 and 5 complete in Progress, with what was verified.

## Left to the builder

- How to share code between the streaming and non-streaming router paths.
- Exact module and file layout on both sides, following the existing patterns (`bt/gateway/`, `apple/BTKit/Sources/BTKit/<Feature>/`).
- Chat pane layout details, within the list-plus-conversation shape above.
- Whether the WebSocket route lives in `gateway.py` or its own router module.
