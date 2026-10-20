# Global hotkey and BT chat implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ⌃⌥Space toggles BT onto Calendar, the server streams text chat over `/chat/ws` with client-supplied tools, and the Mac BT pane reads and continues every conversation.

**Architecture:** The router's existing `respond()` loop gains optional streaming, client tools and per-turn context, so `/chat`, voice and the socket share one routing policy. A new `bt/gateway/chat_ws.py` router owns the socket and calls `respond()`. On the Mac, BTKit gets a `Chat/` feature (wire types, REST and socket clients, an `@Observable` model, views); BTMac adds the Carbon hotkey, a Settings scene and the network entitlement.

**Tech Stack:** Python 3.14, FastAPI, OpenAI SDK against Ollama, SQLite, pytest. Swift 6, SwiftUI, Swift Testing, `URLSessionWebSocketTask`, Carbon `RegisterEventHotKey`.

**Spec:** `docs/superpowers/specs/2026-10-20-hotkey-and-chat-design.md`

## Global Constraints

- No new Python or Swift dependencies.
- Python tests: from `server/`, `uv run python -m pytest -q`.
- Swift tests: from the repo root, `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build`.
- App build: `xcodebuild -project apple/BT.xcodeproj -scheme BTMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/bt-macos-build build`.
- Python files use tabs; Swift files use 4 spaces. Match the surrounding comment density.
- The BTMac Xcode group is not file-system synchronized. Put new Mac-only code in existing BTMac files; new Swift files go in BTKit, which SwiftPM picks up automatically.
- Tool names match `^[a-zA-Z0-9_-]+$`.
- `message.context` is at most 4000 characters. Client tool timeout is 30 seconds.
- Hotkey is ⌃⌥Space, fixed.
- Commit messages: `<type>: <description>`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A server address typed with a trailing slash (`https://bt.example.ts.net/`) must still produce `wss://bt.example.ts.net/chat/ws`, not `//chat/ws`. Pinned in Task 7.
2. The phone posts to `/chat` on the same conversation while a Mac turn runs: the phone gets 409, and when the Mac's turn ends its socket still accepts the next message. Pinned in Task 4.
3. The socket drops (server restart, Mac sleep) and the owner sends again: the model reconnects on that send without a manual retry. Pinned in Task 8.
4. A reply whose `<think>` tag is split across chunks, or that is only an empty think block, shows no stray tag text. Pinned in Task 1.
5. BT is active with its window closed and the hotkey is pressed: Calendar appears instead of BT hiding. Pinned in Task 6.

---

### Task 1: Stream completions and strip thinking across chunks

**Files:**
- Create: `server/bt/llm/streaming.py`
- Test: `server/tests/test_streaming.py`

**Interfaces:**
- Produces:
  - `class ThinkFilter` with `feed(chunk: str) -> str` and `flush() -> str`. Returns only text outside `<think>...</think>`, holding back a possible partial tag at a chunk end.
  - `async def stream_complete(provider: Provider, messages: list, tools: list[dict] | None = None, tool_choice: str | None = None, on_text: Callable[[str], Awaitable[None]] | None = None)` returning `SimpleNamespace(content: str | None, tool_calls: list | None)`, the same shape `_complete` returns. Each tool call is `SimpleNamespace(id, function=SimpleNamespace(name, arguments))`. `content` is the raw full text (thinking included, as `_complete` returns it); `on_text` receives filtered text only.

- [ ] **Step 1: Write the failing tests**

```python
def test_think_filter_handles_split_tags():
    f = ThinkFilter()
    out = f.feed('<thi') + f.feed('nk>plan</th') + f.feed('ink>Hel') + f.feed('lo') + f.flush()
    assert out == 'Hello'

def test_think_filter_drops_unclosed_and_empty_blocks():
    f = ThinkFilter()
    assert f.feed('<think></think>') + f.feed('Hi') + f.flush() == 'Hi'
    g = ThinkFilter()
    assert g.feed('<think>never closed') + g.flush() == ''

def test_think_filter_passes_plain_angle_brackets():
    f = ThinkFilter()
    assert f.feed('a < b') + f.feed(' and c <t') + f.flush() == 'a < b and c <t'

def test_stream_complete_reassembles_tool_calls_and_forwards_text():
    # fake provider.client.chat.completions.create(stream=True) yields chunks:
    #   delta.content 'Let me ', 'check.'
    #   delta.tool_calls [index 0, id 'c1', name 'memory_search', arguments '{"q'] then [index 0, arguments '": "x"}']
    message = asyncio.run(stream_complete(fake_provider, [], on_text=collect))
    assert collected == ['Let me ', 'check.']
    assert message.content == 'Let me check.'
    assert message.tool_calls[0].id == 'c1'
    assert message.tool_calls[0].function.name == 'memory_search'
    assert message.tool_calls[0].function.arguments == '{"q": "x"}'

def test_stream_complete_raises_on_no_chunks():
    # an empty stream raises ValueError, like _complete on no choices
```

- [ ] **Step 2: Run** `uv run python -m pytest -q tests/test_streaming.py`. Expected: FAIL, `bt.llm.streaming` does not exist.

- [ ] **Step 3: Implement `ThinkFilter` and `stream_complete` in `server/bt/llm/streaming.py`**

Add `completion_kwargs(provider, messages, tools, tool_choice) -> dict` to `streaming.py` and make `router._complete` use it, so both paths share the token-limit rules. `streaming.py` imports `Provider` only under `TYPE_CHECKING` to avoid a cycle with `router.py`. Add `stream=True` and accumulate tool call pieces by `index`.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Stream model completions and strip thinking across chunks`

### Task 2: Route streaming, client tools and context through `respond()`

**Files:**
- Modify: `server/bt/llm/router.py` (`respond`)
- Modify: `server/bt/personality/system_prompt.py` (`turn_note`)
- Test: `server/tests/test_router.py`

**Interfaces:**
- Consumes: `stream_complete` from Task 1.
- Produces: `respond(messages, user_text, provider=None, ctx=None, session_id=None, *, context: str | None = None, on_delta: Callable[[str], Awaitable[None]] | None = None, client_tools: list[dict] | None = None, call_client: Callable[[str, str, str], Awaitable[str]] | None = None) -> LLMResponse | None`.
  - `client_tools` are OpenAI tool dicts (`{"type": "function", "function": {...}}`), offered only when `ctx is not None` and tools are enabled, appended after server tools.
  - `call_client(call_id, name, raw_arguments) -> prose`. Calls to a client tool name go there; everything else goes to `dispatch_call`. Client tool names are appended to `ctx.used`.
  - With `on_delta`, each completion uses `stream_complete(..., on_text=on_delta)`. After a mid-turn escalation, later completions pass `on_text=None`. A turn that starts on the cloud (escalation phrase or `provider="cloud"`) still streams.
  - `turn_note(user_text, *, session_id=None, turns=None, context: str | None = None)` appends `f"App context: {context}"` when `context` is set.
  - Callers that pass none of the new arguments behave exactly as today.

- [ ] **Step 1: Write the failing tests** (fakes follow the existing `_complete` monkeypatch style; patch `router.stream_complete` the same way)

```python
def test_streaming_forwards_deltas_and_returns_final_text(monkeypatch): ...
    # fake stream_complete awaits on_text('Hel'), on_text('lo'), returns content 'Hello'
    assert deltas == ['Hel', 'lo'] and result.text == 'Hello'

def test_mid_turn_escalation_stops_deltas(providers, monkeypatch): ...
    # local stream returns '' (degenerate); assert the cloud call received on_text is None
    assert result.compute == 'openai'

def test_client_tool_calls_go_to_the_client(monkeypatch): ...
    # first completion returns tool_call id 'c1' name 'calendar_list_events' args '{}'
    assert offered_names == [*server_tool_names, 'calendar_list_events']
    assert client_calls == [('c1', 'calendar_list_events', '{}')]
    assert tool_message == {'role': 'tool', 'tool_call_id': 'c1', 'content': 'No events'}
    assert 'calendar_list_events' in result.tools_used

def test_client_tools_are_not_offered_without_a_tool_context(monkeypatch): ...
    assert seen_tools is None

def test_context_goes_on_the_latest_user_message(monkeypatch): ...
    assert 'App context: Pomodoro idle' in seen[0][-1]['content']
    assert 'Pomodoro idle' not in seen[0][0]['content']
```

- [ ] **Step 2: Run** `uv run python -m pytest -q tests/test_router.py`. Expected: the five new tests FAIL; existing tests pass.

- [ ] **Step 3: Implement** the signature above. Pick the completion function once per call (`stream_complete` with `on_text` when streaming, else `_complete`); keep the existing loop, escalation and `tool_choice="none"` fallback.

- [ ] **Step 4: Run the whole suite.** Expected: PASS, including `test_system_prompt.py` and the voice tests.

- [ ] **Step 5: Commit** `feat: Stream replies and route client tools through the router`

### Task 3: Store per-turn context

**Files:**
- Modify: `server/bt/transcript/store.py`
- Test: `server/tests/test_store.py`

**Interfaces:**
- Produces: `Turn.context: str | None = None` (last field). `add_turn(..., context: str | None = None)`. `history()` returns it. `as_chat_messages()` is unchanged and never includes context.

- [ ] **Step 1: Write the failing tests**

```python
def test_user_turn_keeps_context(tmp_path):
    store = TranscriptStore(str(tmp_path / 'bt.db'))
    sid = store.new_session()
    store.add_turn(sid, 'user', 'Hi', input_mode='text', context='Pomodoro idle')
    assert store.history(sid)[0].context == 'Pomodoro idle'
    assert 'Pomodoro idle' not in store.as_chat_messages(sid)[0]['content']

def test_existing_database_gains_context_column(tmp_path):
    # create the turns table with the old schema (no context column) via sqlite3, insert a turn,
    # then open TranscriptStore on the same file
    assert store.history(sid)[0].context is None
    store.add_turn(sid, 'user', 'Next', context='x')  # no error
```

- [ ] **Step 2: Run** `uv run python -m pytest -q tests/test_store.py`. Expected: FAIL.

- [ ] **Step 3: Implement.** Add `context TEXT` to `SCHEMA`; after `executescript`, check `PRAGMA table_info(turns)` and `ALTER TABLE turns ADD COLUMN context TEXT` when missing.

- [ ] **Step 4: Run the whole suite.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Store app context on user turns`

### Task 4: `/chat/ws` socket with streaming turns

**Files:**
- Create: `server/bt/gateway/chat_ws.py`
- Modify: `server/bt/gateway/gateway.py` (include the router; export the text validation it shares with `ChatRequest`)
- Test: `server/tests/test_chat_ws.py`

**Interfaces:**
- Consumes: `respond(...)` from Task 2, `add_turn(..., context=)` from Task 3, `store.conversation`, `default_context`, `openai_tools`.
- Produces: `router = APIRouter()` with `@router.websocket("/chat/ws")`, `CLIENT_TOOL_TIMEOUT_SECS = 30.0` (module constant, patched in tests). Task 6 uses the frame shapes below verbatim.

Frames (JSON, `type` field):
- In: `{"type":"hello","tools":[{"name","description","parameters"}]}`, `{"type":"message","text","context"?}`, `{"type":"tool_result","id","ok","content"}`.
- Out: `{"type":"session","session_id"}`, `{"type":"delta","text"}`, `{"type":"tool_call","id","name","args"}`, `{"type":"done","text","compute","tools_used"}`, `{"type":"error","message"}`.

Error copy:
- Unknown session: `"Conversation not found"`, then close with code 1008.
- Busy lease: `"Conversation is busy. Disconnect voice or wait for the current reply."` (same as `/chat`).
- Turn failure: `"Response failed. Try again."`
- Message during a running turn: `"Wait for the current reply."`
- Bad frame or bad JSON: `"Unrecognized message."`
- Blank text: `"Enter a message"`. Context over 4000 characters: `"Context is too long."`
- Bad `hello` (bad name, duplicate, collides with a server tool, or after the first message): `"Tools were rejected: <reason>"`; the connection continues with no client tools.

Behavior: the receive loop runs on the socket; each `message` starts one turn task. The turn takes `store.conversation(session_id)`, stores the user turn with `input_mode="text"` and `context`, builds history, calls `respond(..., context=, on_delta=send delta, client_tools=, call_client=)`, stores the BT turn and sends `done`. `ctx` is `default_context(session_id, "text")` when `CONFIG.tools_enabled`, else `None`.

- [ ] **Step 1: Write the failing tests** (TestClient `websocket_connect`, the `client` fixture pattern from `test_gateway.py`, `chat_ws.respond` monkeypatched with a fake that calls `on_delta`)

```python
def test_new_socket_announces_a_session_and_streams_a_turn(client, monkeypatch):
    # receive session; send message 'Hi'; receive delta 'Hel', delta 'lo', done
    assert done == {'type': 'done', 'text': 'Hello', 'compute': 'ollama', 'tools_used': []}
    assert [t['role'] for t in client.get('/history', params={'session_id': sid}).json()] == ['user', 'bt']

def test_context_is_stored_and_passed_to_the_router(client, monkeypatch): ...
    assert seen_context == 'Pomodoro idle' and history[0]['context'] == 'Pomodoro idle'

def test_unknown_session_is_reported_and_closed(client): ...

def test_busy_conversation_reports_and_socket_stays_usable(client, monkeypatch):
    # hold gateway.store.conversation(sid) open, send message -> error with the busy copy;
    # release, send again -> done

def test_phone_post_during_socket_turn_gets_409(client, monkeypatch):
    # fake respond waits on a threading.Event; POST /chat same session -> 409; set event -> done arrives

def test_bad_frames_and_blank_text_return_errors(client): ...

def test_failed_turn_reports_and_stores_no_reply(client, monkeypatch): ...

def test_hello_rejects_bad_and_colliding_tool_names(client, monkeypatch): ...
    # 'calendar.list' -> error; a server tool name -> error; then a message still completes
```

- [ ] **Step 2: Run** `uv run python -m pytest -q tests/test_chat_ws.py`. Expected: FAIL.

- [ ] **Step 3: Implement** `chat_ws.py` and include its router in `gateway.app`. Validate frames with Pydantic models (a discriminated union on `type`).

- [ ] **Step 4: Run the whole suite.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Add streaming chat socket`

### Task 5: Client tool calls, timeouts and disconnects

**Files:**
- Modify: `server/bt/gateway/chat_ws.py`
- Test: `server/tests/test_chat_ws.py`

**Interfaces:**
- Consumes: Task 4's socket.
- Produces: the `call_client` passed to `respond`. It sends `tool_call` with `args` parsed from the raw JSON (`{}` when invalid), then waits for the matching `tool_result`. Returns `content` on `ok: true`, `f"{name} failed: {content}"` on `ok: false`, and `f"The app did not answer {name} in time."` after `CLIENT_TOOL_TIMEOUT_SECS`. Unknown `tool_result` ids are ignored.

- [ ] **Step 1: Write the failing tests**

```python
def test_client_tool_round_trip(client, monkeypatch):
    # hello with calendar_list_events; fake respond awaits call_client('c1', 'calendar_list_events', '{"day": "today"}')
    assert tool_call == {'type': 'tool_call', 'id': 'c1', 'name': 'calendar_list_events', 'args': {'day': 'today'}}
    # send tool_result ok True 'No events'
    assert done['text'] == 'No events'

def test_failed_client_tool_is_reported_to_the_model(client, monkeypatch): ...
    assert done['text'] == 'calendar_list_events failed: Calendar access is off'

def test_unanswered_client_tool_times_out(client, monkeypatch):
    monkeypatch.setattr(chat_ws, 'CLIENT_TOOL_TIMEOUT_SECS', 0.05)
    assert done['text'] == 'The app did not answer calendar_list_events in time.'

def test_unknown_tool_result_is_ignored(client, monkeypatch): ...

def test_disconnect_mid_turn_cancels_and_stores_no_reply(client, monkeypatch):
    # fake respond blocks; close the socket; the turn's cancellation is observed;
    assert [t['role'] for t in history] == ['user']
```

- [ ] **Step 2: Run** `uv run python -m pytest -q tests/test_chat_ws.py`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement.** Keep pending calls in a dict of `asyncio.Future` keyed by id; on disconnect cancel the turn task, which cancels any pending wait.

- [ ] **Step 4: Run the whole suite.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Route client tool calls over the chat socket`

### Task 6: Global hotkey

**Files:**
- Create: `apple/BTKit/Sources/BTKit/HotkeyAction.swift`
- Modify: `apple/BTKit/Sources/BTKit/ToolSidebar.swift`, `apple/BTKit/Sources/BTKit/ToolSidebarModel.swift`
- Modify: `apple/BTMac/BTMacApp.swift`, `apple/BTMac/PomodoroMenuBar.swift`
- Test: `apple/BTKit/Tests/BTKitTests/HotkeyActionTests.swift`

**Interfaces:**
- Produces:
  - `public enum HotkeyAction: Equatable { case hide, showCalendar; public static func resolve(appIsActive: Bool, mainWindowVisible: Bool) -> HotkeyAction }`. `.hide` only when both are true.
  - `ToolSidebarModel` becomes `public` (`init(modules:)`, `modules`, `selectedModuleID`, `selectedModule`). `ToolSidebar` gains `public init(model: ToolSidebarModel)`; `init(modules:)` stays.

- [ ] **Step 1: Write the failing test**

```swift
@Test func hidesOnlyWhenActiveWithAVisibleWindow() {
    #expect(HotkeyAction.resolve(appIsActive: true, mainWindowVisible: true) == .hide)
    #expect(HotkeyAction.resolve(appIsActive: true, mainWindowVisible: false) == .showCalendar)
    #expect(HotkeyAction.resolve(appIsActive: false, mainWindowVisible: true) == .showCalendar)
    #expect(HotkeyAction.resolve(appIsActive: false, mainWindowVisible: false) == .showCalendar)
}
```

- [ ] **Step 2: Run the Swift tests.** Expected: FAIL, `HotkeyAction` not found.

- [ ] **Step 3: Implement `HotkeyAction` and the public sidebar model.**

- [ ] **Step 4: Run the Swift tests.** Expected: PASS, including the existing sidebar tests.

- [ ] **Step 5: Wire the hotkey in BTMac.** In `BTMacApp.swift`: hold `@State private var sidebar: ToolSidebarModel` built in `init`, pass it to `ToolSidebar(model:)`, and add a small `GlobalHotkey` class wrapping `RegisterEventHotKey` / `InstallEventHandler` for `kVK_Space` with `controlKey | optionKey`. On failure, log through `Logger` and continue. Install it from `PomodoroMenuBarLabel` (the only view alive when the window is closed) with `.onAppear`, using its `openWindow`. The handler computes `mainWindowVisible` as any `NSApp.windows` element with `canBecomeMain && isVisible && !isMiniaturized`, then either `NSApp.hide(nil)` or sets `sidebar.selectedModuleID = "calendar"`, calls `openWindow(id: "main")` and `NSApp.activate()`.

- [ ] **Step 6: Build the app** with the Global Constraints command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Hand check.** Launch the app. From Safari press ⌃⌥Space: BT appears on Calendar. Press again: BT hides and Safari is front. Select Pomodoro, press: BT hides. Close the window with BT still active, press: the window opens on Calendar. Minimize it, press: it returns on Calendar.

- [ ] **Step 8: Commit** `feat: Toggle BT onto Calendar with a global hotkey`

### Task 7: Chat wire types and server clients

**Files:**
- Create: `apple/BTKit/Sources/BTKit/Chat/ChatWire.swift`, `apple/BTKit/Sources/BTKit/Chat/ChatServer.swift`
- Test: `apple/BTKit/Tests/BTKitTests/ChatWireTests.swift`

**Interfaces:**
- Produces:
  - `public enum ServerFrame: Decodable, Equatable { case session(id: String), delta(String), toolCall(id: String, name: String), done(text: String, compute: String, toolsUsed: [String]), error(String), unknown }`. `tool_call.args` is skipped until phase 6; unknown `type` values decode as `.unknown`.
  - `public enum ClientFrame: Encodable, Equatable { case hello(tools: [ClientToolSpec]), message(text: String, context: String?), toolResult(id: String, ok: Bool, content: String) }` with `ClientToolSpec { name, description }` (encodes `parameters` as an empty object schema `{"type":"object","properties":{}}` for now). Encodes to the Task 4 frame shapes with snake_case keys and no `context` key when nil.
  - `public struct ChatSessionSummary: Decodable, Identifiable, Equatable { id, label, updatedAt: Double }` and `public struct ChatTurn: Decodable, Identifiable, Equatable { id, ts: Double, role: String, text: String, compute: String? }`.
  - `public struct ChatEndpoints { init?(serverAddress: String); sessionsURL; historyURL(sessionID:); socketURL(sessionID: String?) }`. Accepts `http`/`https` with a host; returns nil otherwise. Maps to `ws`/`wss` for the socket.
  - `public protocol ChatAPI: Sendable { func sessions() async throws -> [ChatSessionSummary]; func history(sessionID: String) async throws -> [ChatTurn] }` with `URLSessionChatAPI(endpoints:)`.
  - `public protocol ChatSocket: AnyObject, Sendable { func send(_ frame: ClientFrame) async throws; func receive() async throws -> ServerFrame; func close() }` with `URLSessionChatSocket(url:)` over `URLSessionWebSocketTask`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func decodesEveryServerFrame() throws { /* session, delta, tool_call with args, done, error, an unknown type */ }
@Test func encodesClientFramesInTheServerShape() throws {
    // message without context has no "context" key; tool_result uses "ok" and "content"
}
@Test func endpointsHandleTrailingSlashesAndSchemes() {
    let e = ChatEndpoints(serverAddress: "https://bt.example.ts.net/")!
    #expect(e.socketURL(sessionID: nil).absoluteString == "wss://bt.example.ts.net/chat/ws")
    #expect(e.socketURL(sessionID: "s 1").absoluteString == "wss://bt.example.ts.net/chat/ws?session_id=s%201")
    #expect(ChatEndpoints(serverAddress: "http://127.0.0.1:8080")!.sessionsURL.absoluteString == "http://127.0.0.1:8080/sessions")
    #expect(ChatEndpoints(serverAddress: "bt.example.ts.net") == nil)
    #expect(ChatEndpoints(serverAddress: "ftp://x") == nil)
}
@Test func decodesSessionsAndHistoryFromServerJSON() throws { /* updated_at, null compute, extra keys like context ignored */ }
```

- [ ] **Step 2: Run the Swift tests.** Expected: FAIL.

- [ ] **Step 3: Implement.** Use `JSONDecoder` with `.convertFromSnakeCase`. Non-2xx REST responses throw an error carrying the server's `detail` when present.

- [ ] **Step 4: Run the Swift tests.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Add chat wire types and server clients`

### Task 8: Chat model

**Files:**
- Create: `apple/BTKit/Sources/BTKit/Chat/ChatModel.swift`
- Test: `apple/BTKit/Tests/BTKitTests/ChatModelTests.swift`

**Interfaces:**
- Consumes: Task 7 types.
- Produces: `@MainActor @Observable public final class ChatModel` with
  - `init(makeAPI: @escaping (ChatEndpoints) -> any ChatAPI = URLSessionChatAPI.init, makeSocket: @escaping (URL) -> any ChatSocket = URLSessionChatSocket.init)`
  - `var serverAddress: String` (setting it resets state and reloads), `var endpoints: ChatEndpoints? { get }`
  - `private(set) var sessions: [ChatSessionSummary]`, `var selectedSessionID: String?`, `private(set) var turns: [ChatTurn]`, `var draft: String`, `private(set) var streamingText: String?`, `private(set) var errorMessage: String?`, `var isSending: Bool { streamingText != nil }`
  - `func loadSessions() async`, `func select(_ id: String?) async`, `func startNewConversation()`, `func send() async`

Behavior:
- `select` closes any socket, loads history, clears streaming. `startNewConversation` clears selection and turns; the first `send` opens the socket without a session id and adopts the id from the `session` frame.
- `send` trims `draft`; ignores blank text or a send while `isSending`. It opens the socket if there is none, sending `hello(tools: [])` first. It appends a local user turn, clears `draft`, sets `streamingText = ""` and sends `message(text:context: nil)`. If writing the frame fails, it restores `draft`, removes the local turn and sets `errorMessage`.
- The receive loop appends `delta` to `streamingText`. On `done` it appends a BT turn with `done.text` and `compute`, sets `streamingText = nil` and reloads sessions. On `error` it sets `errorMessage` and `streamingText = nil`. On `toolCall` it replies `toolResult(ok: false, content: "This app does not run tools yet.")`. If `receive` throws, it drops the socket, ends streaming, and sets `"Lost connection to BT. Try again."` only if a reply was in flight.
- No valid address: `errorMessage` stays nil, and the view shows the setup state from `endpoints == nil`.

- [ ] **Step 1: Write the failing tests** with a `FakeChatAPI` and a `FakeChatSocket` (an inbox of frames the test pushes, and a record of sent frames)

```swift
@Test func deltasAccumulateAndDoneReplacesThem() async { /* push delta "Hel", delta "lo", done "Hello!" */
    #expect(model.turns.last?.text == "Hello!" && model.streamingText == nil) }
@Test func newConversationAdoptsTheServerSessionID() async { }
@Test func firstSendSaysHelloWithNoTools() async { #expect(socket.sent.first == .hello(tools: [])) }
@Test func errorFrameLeavesTheComposerUsable() async { /* error -> errorMessage set, isSending false, next send goes out */ }
@Test func droppedSocketReconnectsOnTheNextSend() async { /* receive throws; next send makes a second socket */
    #expect(factory.made.count == 2) }
@Test func failedWriteRestoresTheDraft() async { }
@Test func toolCallsAreDeclined() async { }
@Test func invalidAddressShowsSetupState() { #expect(ChatModel(...).endpoints == nil) }
```

- [ ] **Step 2: Run the Swift tests.** Expected: FAIL.

- [ ] **Step 3: Implement `ChatModel`.**

- [ ] **Step 4: Run the Swift tests.** Expected: PASS.

- [ ] **Step 5: Commit** `feat: Add chat model with streaming replies`

### Task 9: Chat pane, Settings and network access

**Files:**
- Create: `apple/BTKit/Sources/BTKit/Chat/ChatView.swift`, `apple/BTKit/Sources/BTKit/Chat/ChatSettingsView.swift`
- Modify: `apple/BTKit/Sources/BTKit/BTModule.swift`, `apple/BTMac/BTMacApp.swift`, `apple/BTMac/BTMac.entitlements`, `apple/README.md`

**Interfaces:**
- Consumes: `ChatModel` from Task 8.
- Produces: `BTModule(chat: ChatModel = ChatModel())`, so existing `BTModule()` calls and tests keep working; `ChatSettingsView()` storing `@AppStorage("serverAddress")`. `BTModule` keeps `id "bt"`, no tools, no snapshot.

- [ ] **Step 1: Build the views.** `ChatView`: a conversation list (labels, newest first, a New Conversation button, a refresh button) beside the conversation (turns, the streaming bubble, a composer that sends on Return). Replies render with `AttributedString(markdown:)`, falling back to plain text. Replies with `compute == "openai"` show a small "Cloud" label. `errorMessage` shows inline with a Retry button that calls `loadSessions()`. When `endpoints == nil`, show "Set your BT server address in Settings." with a `SettingsLink` on macOS. The view reads `@AppStorage("serverAddress")` and pushes it into `model.serverAddress` on appear and on change. `ChatSettingsView`: one text field labeled "Server address", placeholder `https://bt.example.ts.net`, with an inline "Enter a full address starting with https://" note when `ChatEndpoints(serverAddress:)` is nil.

- [ ] **Step 2: Wire the app.** In `BTMacApp`, create one `ChatModel` in `init`, pass `BTModule(chat:)` to the sidebar, and add `Settings { ChatSettingsView() }`. Add `com.apple.security.network.client` to the entitlements.

- [ ] **Step 3: Run the Swift tests and build the app.** Expected: PASS and `BUILD SUCCEEDED`.

- [ ] **Step 4: Hand check against a local server.** In `server/`, run `bt-dev` (or `uv run python -m bt.main`), open Settings and enter `http://127.0.0.1:8080`. Confirm: existing conversations list, including one started from the browser client; selecting one shows its history; a new message streams and the list reorders; the browser client sees the Mac's message after a reload; with the server stopped, sending shows the lost-connection message, and after a restart the next send works.

- [ ] **Step 5: Update `apple/README.md`.** Describe the BT chat pane and the Settings address, change "It requests no microphone or network access yet" to say it requests outgoing network access for the BT server, and mention the ⌃⌥Space hotkey.

- [ ] **Step 6: Commit** `feat: Add BT chat pane with server address setting`

### Task 10: Plan and docs

**Files:**
- Modify: `docs/superpowers/plans/2026-10-19-monorepo-and-mac-client.md`, `docs/DEPLOYMENT.md`, `AGENTS.md` (only if a new mistake was learned)

- [ ] **Step 1: Update the monorepo plan.** Phase 9 keeps the browser client until a native iOS app replaces it; add a phase after 9 for the iOS app. Add the owner's later goals: link a focus session to a calendar event, show the focused percentage on the event, a tool for "when am I most productive", and briefings ("Start the day", "Catch me up"). Put the first two under phase 8 and the rest under phases 6 and 8. Add Progress entries for phases 4 and 5 stating what was verified and what was not.

- [ ] **Step 2: Note `/chat/ws` in `docs/DEPLOYMENT.md`.** One line: the Mac app uses the same HTTPS Serve address and needs no extra port.

- [ ] **Step 3: Run both test suites** (Python and Swift commands from Global Constraints). Expected: PASS. Report counts.

- [ ] **Step 4: Commit** `docs: Record phases 4 and 5 and the owner's later goals`
