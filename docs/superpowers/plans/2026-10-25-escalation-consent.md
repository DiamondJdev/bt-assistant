# Ask Before Model Escalation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if requested. Steps use checkbox syntax for tracking. Do not commit or create a branch without the owner's request.

**Goal:** Ask before switching models on text and voice, with conversation-wide approval as the primary action and one-reply approval as the alternative.

**Architecture:** Keep routing in the existing text router and Pipecat voice service. Add one small consent module backed by the existing transcript database for grants; pending requests stay in memory and expire. Text waits for a structured decision without restarting its tool loop. Voice ends its approval prompt normally, saves the unfinished context, and resumes it after a button or spoken decision, rather than blocking the pipeline while waiting for speech.

**Tech Stack:** Existing Python/FastAPI, SQLite, Pipecat, SwiftUI, and browser JavaScript. No new dependencies.

**Spec:** The owner's request: ask before switching on text and voice; approval lasts for the conversation unless the owner chooses one reply. The behavior section below records implementation choices. Read `2026-10-25-agent-pipeline-hardening.md` for future routing changes; this plan supersedes its automatic-switch rules, not its other work.

## Behavior

1. Before a switch, explain the reason, destination provider/model, and whether conversation context and completed tool results will leave the local machine. Offer **Allow for conversation**, **Allow once**, and **Don't switch**. The first action is prominent, never automatically selected or submitted.
2. A conversation grant belongs to the persisted session and exact destination `(provider, model)`. It works across text, voice, reconnects, and restarts. A different conversation or destination needs approval. This target-specific scope is a design choice: approving today's default cloud model must not silently authorize the future stronger model. Normal turns still start on the configured default; permission is not a sticky model selection.
3. Allow once covers the original unfinished reply, including its remaining tool/model rounds. It creates no persistent grant and ends on completion, cancellation, or failure. Denial, expiry, missing client support, invalid decisions, and disconnect never authorize a switch. Pending requests expire after 120 seconds and cannot survive reconnect or restart.
4. Starting on the configured default is not escalation. A phrase can request a switch, never authorize one. `provider="local"` stays local even with a phrase or prior grant. A missing cloud key produces an unavailable explanation without a useless approval prompt. Retrying the same model requires no escalation permission.
5. Keep the current response/tool context when resuming. Do not restart the original request, append the user request twice, or repeat completed tool writes. Never retry voice after any model text or tool-call delta has been emitted. Permission to use a model does not approve its tools.

## Global Constraints

- Preserve the existing dirty hardening plan and `.claude/`. Write only files needed for this feature; refresh status before implementation.
- Implement against current code. Do not implement Terra, tier limits, compaction, background tasks, budgets, or a general policy engine here. Target identity is provider/model so later tiers can use the same check.
- Reuse `TranscriptStore` locking/migration conventions, existing conversation leases, gateway authentication/origin rules, Swift tool-card styling, and existing test doubles. Model consent has its own handler, not a fake tool call.
- Store only granted destinations in SQLite. Keep pending IDs, original contexts, and continuations in memory. Do not put prompts, tool arguments, or consent contents in diagnostics.
- Do not claim live model, microphone, or native app validation from mocked tests. Do not launch the app or deployment services without approval.

## Review Focus

1. A stale, replayed, or other-session decision must not grant permission or revive a cancelled reply. Cover in Task 1 and gateway tests.
2. Once approval must survive several model/tool rounds but never spill into the next reply. Cover in Task 2 and Task 3.
3. Speech/VAD interruption during an approval prompt must not deadlock, authorize a switch, or replay a completed tool. Cover with real Pipecat frame processing and fake providers in Task 3.
4. REST disconnect, socket loss, server restart, and duplicate decisions must release pending state; stored conversation grants alone survive. Cover in Tasks 1–3.
5. A stored cloud grant must not override explicit-local routing or authorize a new model ID. Cover in Tasks 1–3; include the future-tier integration checklist in Task 5.

## Task 1: Consent State and Session Grants

**Files:** Create `server/bt/llm/escalation.py` and `server/tests/test_escalation.py`. Modify `server/bt/transcript/store.py` and `server/tests/test_store.py`.

**Interfaces:**

- Add `sessions.escalation_models TEXT NOT NULL DEFAULT '[]'`, migrating existing databases with the same `PRAGMA table_info` pattern as `turns.context`. Store a JSON list of `[provider, model]` pairs; never overwrite other session fields.
- `TranscriptStore.escalation_allowed(session_id: str, provider: str, model: str) -> bool` and `allow_escalation(session_id: str, provider: str, model: str) -> None`. Both validate the session, run under the existing lock, and make duplicate grants harmless.
- `EscalationRequest`: immutable `id`, `session_id`, `provider`, `model`, `reason`, and `message`. `reason` is `requested`, `local_error`, or `empty_reply`. The server builds all routing/disclosure fields; clients submit only a request ID and decision.
- `EscalationConsent(store)` owns one pending request per session. `begin(session_id, provider, model, reason, *, on_decision=None) -> EscalationRequest`, `pending(session_id) -> EscalationRequest | None`, `async wait(session_id, request_id) -> str`, `async resolve(session_id, request_id, decision) -> None`, and `cancel(session_id, request_id) -> None`. Decisions are exactly `conversation`, `once`, or `deny`.
- `begin` creates a UUID and a 120-second expiry using the event loop. `wait` serves text callers and returns `deny` on expiry; cancellation raises `asyncio.CancelledError`. Optional `on_decision` serves voice continuations without a waiting LLM call. Resolve validates session/ID/expiry, consumes the request exactly once, persists a conversation grant before resuming, and invokes at most one continuation. Cancellation and expiry release the request/context; cancellation must not invoke a successful continuation. A write failure must not resume generation.
- A per-reply set of approved `(provider, model)` pairs carries once permission. Keep it on the active reply/voice continuation, not on a singleton or session row. No session ID and no interactive requester means no new permission.

- [ ] Write failing tests: old database migration preserves transcripts; grants survive reopening the store; grants do not cross sessions/models; once and deny leave the database unchanged; stale/wrong-session/duplicate decisions cannot resolve; expiry/cancellation releases state; failed persistence cannot authorize a call.
- [ ] Run `cd server && uv run python -m pytest -q tests/test_escalation.py tests/test_store.py`; confirm the new assertions fail for missing behavior.
- [ ] Implement the store methods and consent module. Use the existing single-process deployment assumption; no separate event bus, database connection, or durable continuation queue.
- [ ] Run the same tests; require all assertions to pass.

## Task 2: Text Routing and Both Gateways

**Files:** Modify `server/bt/llm/router.py`, `server/bt/gateway/chat_ws.py`, `server/bt/gateway/gateway.py`, `server/tests/test_router.py`, `server/tests/test_chat_ws.py`, and `server/tests/test_gateway.py`.

**Interfaces:**

- Add keyword-only `request_escalation: Callable[[str, str, str], Awaitable[str]] | None = None` to `respond`; arguments are target provider, target model, and reason. It returns the validated decision from the gateway consent handler. No callback means a switch cannot acquire permission. Check stored session grants or reply-local permission before requesting.
- Put the check before constructing/contacting the destination provider at every switch site: phrase/explicit-cloud selection, local exception, and degenerate local response. Preserve `working`, completed tool results, telemetry, and current loop position. Explicit-local routing takes precedence.
- Declining a requested upgrade continues on the starting model. Declining fallback ends with a plain explanation; retain usable local prose where available. An empty/unavailable local model must not report fabricated task completion. Define one internal `EscalationDeclined` exception for the unavailable-fallback case; gateway handlers catch it before generic 502 handling.
- WebSocket server frame: `{type: "escalation_request", id, session_id, provider, model, reason, message}`. Client frame: `{type: "escalation_decision", id, decision}`. Resolution frame: `{type: "escalation_resolved", id, decision}`; use `expired` or `cancelled` for those endings. The connection supplies session identity; never trust a decision's destination or client-supplied session.
- Handle decisions in `_Connection.on_frame` while `run_turn` awaits consent. Do not hold the receive loop or acquire another conversation lease for a decision. Clear pending state in the active turn's cleanup and on disconnect; retain tool-result handling unchanged.
- Keep successful REST `/chat` request/response shapes unchanged. Add `GET /sessions/{session_id}/escalation` returning `{pending: request-or-null}` and `POST /sessions/{session_id}/escalation` accepting `{id, decision}`. Validate session/decision, inherit existing gateway protections, return 404 for an unknown session and 409 for an expired/mismatched request. These endpoints do not acquire the busy conversation lease.
- REST `/chat` supplies the same requester and waits on it. Check `Request.is_disconnected()` while waiting, at one-second intervals; disconnect cancels permission/continuation and releases the lease. A denied or expired fallback becomes a normal explanatory reply, not a generic server failure. Direct `respond` callers without a callback may use an existing session grant but cannot initiate a silent switch.

- [ ] Write failing tests proving zero destination calls before approval; conversation/once/deny outcomes; once across multiple tool rounds; no completed-tool replay; local override; missing key; no callback; live WS receive-loop decisions; REST concurrent poll/decision; REST disconnect and lease release; unchanged successful response fields.
- [ ] Run `cd server && uv run python -m pytest -q tests/test_router.py tests/test_chat_ws.py tests/test_gateway.py` and confirm the new behavior fails.
- [ ] Implement routing checks and gateway handlers using Task 1. Preserve preexisting conversation grants across transport cleanup; discard only pending/once state.
- [ ] Run the same suites; require all assertions to pass.

## Task 3: Voice Approval Without Blocking Speech

**Files:** Modify `server/bt/voice/routing.py`, `server/bt/voice/pipeline.py`, and `server/bt/voice/routes.py`. Create `server/bt/voice/escalation.py` and `server/tests/test_voice_escalation.py`. Extend `server/tests/test_voice_routing.py`, `server/tests/test_voice_pipeline.py`, and `server/tests/test_voice_routes.py`.

**Interfaces and flow:**

- Apply the same stored-grant/reply-permission check in `RoutedLLMService` before starting cloud on a phrase or pre-output fallback. Keep the existing no-switch-after-text/tool-delta rule, stream closure, and cloud-error behavior.
- On missing permission, retain an isolated copy of the unfinished `LLMContext` messages/tools plus destination and reply-local permissions. Register one pending request with Task 1. Emit the structured request to the voice socket. Return a synthetic completion containing the server-written approval prompt so normal Pipecat TTS finishes the turn. Do not await the decision inside `get_chat_completions`; do not call another model to phrase the question. Mark this prompt with no model compute attribution.
- Spoken copy: **"Use [provider/model]? [disclosure] Say 'yes' to allow it for this conversation, 'just this reply' to allow it once, or 'no' to stay with the current model."** A stored grant skips this prompt. An unavailable destination never prompts.
- Add `VoiceEscalationInput(FrameProcessor)` immediately after STT and before `aggregators.user()`. Only while a request is pending, consume final `TranscriptionFrame` decisions. Normalize case, outer whitespace, and terminal punctuation; accept exact `yes`/`allow for conversation`, `just this reply`/`allow once`, and `no`/`don't switch`. Never accept substrings, interim speech, arbitrary model output, or historical transcript text as approval.
- An unrelated final utterance cancels the pending request and passes through as a new ordinary turn. Silence expires the request. Control utterances never become the resumed task's model input; existing transcript recording may retain what the owner said, but it is not authorization on a later turn.
- The voice `on_decision` callback restores the saved unfinished context and queues `LLMContextFrame` through the existing worker. It resumes on the approved destination, or on the original model for a declined optional upgrade. Declined/expired fallback returns the same unavailable explanation as text without replaying tools. Remove approval prompt/control turns from the resumed model context by restoring the snapshot, not by removing guessed list positions.
- Button decisions use Task 2's POST endpoint. Both button and spoken decisions consume the same pending ID; races resume once. Clean up pending requests and saved contexts when the worker disconnects, is cancelled, or times out. Only persistent grants survive reconnect. Keep `JSONFrameSerializer`'s audio-input contract unchanged.

- [ ] Add failing fake-provider tests: prompt makes no cloud call; yes grants the session; once covers tool follow-ups only; no/expiry/missing key fails closed; unrelated speech cancels; ambiguous/interim speech never approves; button/speech races resume once; restored context retains completed tool results without repeating writes.
- [ ] Add a real Pipecat frame-processing test with fake STT/TTS/providers: request, finish spoken prompt, VAD interruption, final spoken decision, resumed cloud response. Assert the worker processes the second utterance without deadlock, the original question is answered once, and no cloud call precedes the decision. Also pin no fallback after partial speech or a tool-call delta.
- [ ] Run `cd server && uv run python -m pytest -q tests/test_voice_escalation.py tests/test_voice_routing.py tests/test_voice_pipeline.py tests/test_voice_routes.py`; implement the adapter and routing changes until all assertions pass. Do not replace the frame-processing test with direct method calls alone.
- [ ] Verify cancellation closes streams, clears the saved context, and releases the existing voice conversation lease. Test reconnect preserves conversation permission but cannot revive a pending/once grant.

## Task 4: Native and Browser Choices

**Files:** Modify `apple/BTKit/Sources/BTKit/Chat/ChatWire.swift`, `apple/BTKit/Sources/BTKit/Chat/ChatModel.swift`, and `apple/BTKit/Sources/BTKit/Chat/ChatView.swift`; modify `apple/BTKit/Sources/BTKit/Screens/BT/BTConversation.swift` and `apple/BTKit/Sources/BTKit/Screens/BT/BTLive.swift`. Extend `apple/BTKit/Tests/BTKitTests/ChatWireTests.swift`, `apple/BTKit/Tests/BTKitTests/ChatModelTests.swift`, and `apple/BTKit/Tests/BTKitTests/BTLiveTests.swift`. Modify `server/bt/client/app.mjs`, `server/bt/client/index.html`, and `server/bt/client/style.css` only where the approval panel needs markup. Create `server/bt/client/escalation.mjs` and `server/tests/escalation.test.mjs` for the browser controller's small testable state/transport behavior.

**Interfaces and behavior:**

- Swift adds `EscalationApproval` and a separate `pendingEscalation` property. Decode request/resolved frames; send `ClientFrame.escalationDecision(id:decision:)`. Expose `ChatModel.decideEscalation(id:decision:)`; reject repeat taps locally while awaiting server resolution. This action does not execute or approve a tool.
- Render the same three labeled actions in both native chat views, reusing existing card styling. Show destination/reason/disclosure in the card and a waiting status while suspended. Clear the card on resolution, error, thread switch, and socket loss. Preserve draft, tool approvals, and stream state independently. Include keyboard/accessibility labels; never auto-submit the primary action.
- Browser text remains REST. Ensure a session exists via existing `POST /sessions` before starting `/chat`; while that request is in flight, poll Task 2's pending endpoint once per second. Stop polling when the request completes, is aborted, or the session changes. Render an inline panel rather than a blocking browser confirmation dialog.
- Browser voice uses `escalation_request` and `escalation_resolved` socket messages to show/clear the same panel; decisions POST to the matching session/ID. Keep push-to-talk available while pending. Show the spoken choices as text too. No browser text transport migration is needed.
- `escalation.mjs` owns only panel/poll/decision state with injectable fetch/timers for tests. Do not refactor voice connection management or introduce a generic client framework. Native currently exposes text chat, not a voice transport; do not build native voice as part of this change.

- [ ] Write failing Swift tests for wire cases, all three actions, once-vs-conversation payloads, duplicate taps, pending cleanup, and coexistence with tool approvals. Write browser Node tests for REST polling lifetime, first-session creation, voice controls, matching request IDs, decision failures, and session changes.
- [ ] Run `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build --filter 'ChatWireTests|ChatModelTests|BTLiveTests'` and `node --test server/tests/escalation.test.mjs`; confirm the new assertions fail before implementation.
- [ ] Implement UI/wire handling. On a failed decision submission, keep the request visible with an actionable retry message; do not treat failure as approval. The server remains authoritative.
- [ ] Run the same tests; require all assertions to pass. Inspect the browser panel with fake data; ask before starting the native app or live voice services.

## Task 5: Integration, Documentation, and Handoff

**Files:** Update the existing routing section in `docs/DESIGN.md` and the relevant current test fixtures. Do not edit the dirty hardening plan; record its integration requirements here.

- [ ] Document conversation-vs-once semantics, target-specific grants, the 120-second timeout, spoken controls, and REST/WS frames. Explain that cloud permission covers conversation context/tool results and is separate from permission to execute tools.
- [ ] Verify hardening compatibility: Tasks 1 and 2 must check this consent gate before every tier switch, including local-to-default fallback and default-to-escalation. New model IDs require fresh permission. Task 15 must pass its real `session_id`; background work can use an existing grant but cannot create one without an interactive owner. Its fallback must report that approval is needed, not silently escalate. Existing `one_shot` no-switch behavior remains unchanged. Do not implement those future tasks here.
- [ ] Run `cd server && uv run python -m pytest -q`, `node --test server/tests/*.test.mjs`, `swift test --package-path apple/BTKit --scratch-path /tmp/btkit-build`, and `git diff --check`. Report unrelated failures without expanding scope.
- [ ] With permission to run services, smoke-test text-to-voice and voice-to-text grants in one session, a once-approved reply followed by a fresh prompt, denial, session change, disconnect, and partial voice failure. Verify actual destination calls, not only badges. If services/keys/hardware are unavailable, mark these checks unperformed.
- [ ] Review `git status --short` and the focused diff. Report which paths work, which validation ran, and any remaining runtime risk. Leave unrelated changes, commits, branches, and deployments untouched.

## Execution Recommendation

Use native execution in this session: the five tasks share a small consent contract, and implementing the transport adapters together avoids delegation overhead. Review this plan before implementation; the next step is Task 1's failing tests.
