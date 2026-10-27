# Agent Pipeline Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build on PR #17, which made OpenAI (GPT-5.6 Luna) the default through `BT_LLM_PROVIDER`. Add GPT-5.6 Terra for escalation, then harden the tool, memory and conversation pipeline, and add background tasks that outlive a turn. Every task keeps working in `ollama` mode, where Qwen is the only model.

**Architecture:** A new `bt/llm/tiers.py` names three tiers: `default` (Luna), `escalation` (Terra) and `local` (Qwen through Ollama), and holds per-tier limits. `BT_LLM_PROVIDER` still decides whether a turn starts on `default` or `local`. The text router and the voice service both pick a tier through it. Model-dependent sizes (history, tool output, tool rounds, output tokens) come from the current tier's `Limits`.

All tool calls already pass through `run_tool` in `bt/tools/registry.py`. Error codes, surface checks and the confirmation check go there. The loop guard and parallel tool execution sit one level up, in the router's tool loop for text and the Pipecat bridge for voice. Search moves to SQLite FTS5. `bt/transcript/compaction.py` folds old turns into a stored summary. `bt/tasks/` adds a durable background task queue in the same SQLite file, run by one worker loop started with the app.

**Tech Stack:** Python 3.14, FastAPI, Pipecat, the OpenAI SDK's Chat Completions API (against OpenAI for Luna and Terra, and against Ollama's `/v1` for Qwen3 8B), stdlib `sqlite3` (FTS5 is present: SQLite 3.54.1 was checked with `tokenize="porter unicode61"`), pytest. BT stays on Chat Completions so one request shape serves all three tiers; see "Not in this plan" for the Responses API.

**Source:**
- Cindy (github.com/makecindy/cindy), Tasks 3 to 9: `packages/maker-core/src/agents/shared/loop-guard.ts`, `packages/lizi-mcps/src/tool-error-telemetry.ts`, `packages/lizi-mcps/src/tool-call-authority.ts`, `packages/lizi-mcps/src/memory/*`, `packages/maker-core/src/memory/flush-controller.ts`.
- OpenClaw: [session pruning](https://docs.openclaw.ai/concepts/session-pruning) (Task 10), [compaction](https://docs.openclaw.ai/concepts/compaction) (Task 11), and its cron and queue lanes (Tasks 15 and 16).
- Hermes Agent: [context compression](https://hermes-agent.nousresearch.com/docs/developer-guide/context-compression-and-caching) (Task 11), the [agent loop](https://hermes-agent.nousresearch.com/docs/developer-guide/agent-loop) (approval callback, parallel tool calls with results in call order, periodic memory review; Tasks 13, 14 and 17).
- Manus: [Context Engineering for AI Agents](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus) (stable prefix for the KV cache, plan recitation for long tasks, errors kept in context; Tasks 11 and 15).
- Lindy: approval before a step that changes data (Task 13). Lindy is closed source; this is the general pattern from third-party write-ups. The Mac app already does it for calendar writes (`ToolModule.needsApproval`).
- OpenAI: the [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) and [Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) model pages (1.05M context, 128K output, reasoning effort `none` to `max`, Chat Completions supported) and the [prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching) (cache writes cost 1.25×, reads 0.1×; changing tools, `parallel_tool_calls` or `reasoning_effort` clears the cache).

## Global Constraints

- Run Python from `server/`: `uv run python -m pytest -q` (plain `uv run pytest` breaks on hidden `.pth` files; see AGENTS.md).
- No new dependencies.
- PR #17's provider rules hold. `BT_LLM_PROVIDER` (`openai` by default, or `ollama`) picks the starting model, read once at startup. `openai` mode requires `OPENAI_API_KEY` and fails startup without one. OpenAI failures fail the turn and never fall back to Qwen. `ollama` mode is local-first with optional OpenAI fallback and escalation. Every task must keep working in `ollama` mode with no key, at `LOCAL_LIMITS`. Task 17 is the one cloud-only feature, and it switches itself off in `ollama` mode.
- Model-dependent sizes come from `Limits` in `bt/llm/tiers.py` (Task 1). Don't add size literals elsewhere.
- Tests follow PR #17: `tests/conftest.py` sets `BT_LLM_PROVIDER=ollama`, so suites never need a key. OpenAI-mode tests patch `replace(CONFIG, llm_provider='openai', openai_api_key='test-key')` (or use `test_router.py`'s `openai_mode` fixture). No-key tests set `replace(CONFIG, openai_api_key='')`.
- Keep the system prompt stable. Per-turn facts go through `turn_note`. Never vary the tool list, `reasoning_effort` or `parallel_tool_calls` between turns of one tier.
- Diagnostics and log lines added here carry tool names, codes, counts, ids, tiers and ratios only. Never message text, tool arguments or task goals.
- Tools return prose strings. Errors are prose too, starting `Error <CODE>: `.
- Tabs for indentation, matching the existing server code.
- Commit messages: `<type>: <description>`, no attribution lines (user rule).

## Review Focus

1. In `openai` mode, Luna fails after a tool already ran. The error reaches the Pilot, the tool doesn't run again, and Qwen is never called. Pinned in Tasks 1 and 2.
2. An explicit `provider="local"` turn in `openai` mode sends Qwen a history that fits `LOCAL_LIMITS`. Pinned in Task 11.
3. "Try this again" matches an escalation phrase. In `ollama` mode without `OPENAI_API_KEY` it gets a local answer, not an error. Pinned in Task 1.
4. A voice session spans many turns on one `ToolContext`. Asking the same thing twice in two turns must not trip the loop guard. Pinned in Task 5.
5. Search text made of FTS5 syntax (`"NEAR(* -`) or only filler words returns no results and never raises. Pinned in Task 6.
6. An existing `bt.sqlite3` with turns but no FTS table has those turns searchable after upgrade. Pinned in Task 7.
7. `memory_consolidate` listing its own target as a source keeps the target. An unknown source changes nothing. Pinned in Task 8.
8. With `BT_CONTEXT_LIMIT` unset, the context watch is fully off. Pinned in Task 9.
9. Clearing old tool output keeps every assistant tool call paired with its tool message. Pinned in Task 10.
10. A failed summary call still bounds the history and never fails the Pilot's turn. Pinned in Task 11.
11. A turn cut off after `calendar_create_event` ran tells the next turn that it ran. Pinned in Task 12.
12. A tool that needs confirmation can't be confirmed by a second call in the same turn, or by a later segment of a background task. Pinned in Tasks 13 and 15.
13. Two `memory_write` calls in one round never run at the same time, on text or voice. Pinned in Task 14.
14. BT restarts while a background task runs. The task resumes, gives up after three attempts, and the Pilot is told either way. Pinned in Task 16.

---

### Task 1: Model tiers for text: Luna, Terra and Qwen

PR #17 added `BT_LLM_PROVIDER` (default `openai`) and made it the only switch between OpenAI and Ollama. That PR's rules stay in force here:
- `openai` mode needs `OPENAI_API_KEY`. `Config.validate_llm()` fails startup without one.
- In `openai` mode a failed OpenAI call fails the turn. BT never falls back to Ollama, and a degenerate reply is not retried.
- `ollama` mode keeps local-first routing with OpenAI fallback and escalation. It can start without a key.

This task adds Terra as the escalation model and per-tier limits. It also fixes `ollama` mode without a key. Today an escalation phrase like "try this again" crashes the turn there, and an honest local "I don't know" turns into "Response failed".

At `CLOUD_LIMITS`, a full Luna turn is about 40k input tokens: roughly $0.008 uncached and $0.0008 from the cache. Terra is ten times that.

**Files:**
- Create: `server/bt/llm/tiers.py`
- Modify: `server/bt/config.py` (`escalation_model`)
- Modify: `server/bt/llm/router.py` (`Provider.tier`, `_provider`, `respond`, `LLMResponse.model`, `ModelUnavailable`; remove `MAX_TOOL_ITERATIONS`)
- Modify: `server/bt/llm/streaming.py` (`completion_kwargs`; remove `MAX_TOKENS`)
- Modify: `server/bt/llm/telemetry.py` (`output_limit` from `Limits`, `cached_tokens`)
- Modify: `server/bt/gateway/chat_ws.py` (`run_turn`, `done` frame), `server/bt/gateway/gateway.py` (`chat`), `server/bt/devui/routes.py` (`/dev/config`)
- Modify: `server/.env.example`, `docs/DESIGN.md` ("Routing: local vs. cloud")
- Test: `server/tests/test_tiers.py` (new), `server/tests/test_router.py`, `server/tests/test_streaming.py`, `server/tests/test_telemetry.py`, `server/tests/test_chat_ws.py`, `server/tests/test_gateway.py`

**Interfaces:**
- Produces, in `tiers.py`:
  - `@dataclass(frozen=True) class Limits: history_chars: int; tool_result_chars: int; turn_tool_chars: int; tool_rounds: int; max_output_tokens: int`
  - `LOCAL_LIMITS = Limits(16_000, 4_000, 12_000, 10, 2_048)` and `CLOUD_LIMITS = Limits(160_000, 16_000, 64_000, 25, 8_192)`
  - `TEXT_EFFORT = {"default": "low", "escalation": "medium"}` and `VOICE_EFFORT = {"default": "none", "escalation": "low"}`
  - `openai_default() -> bool`: `CONFIG.llm_provider == "openai"`
  - `cloud_configured() -> bool`: `OPENAI_API_KEY` is set and not blank. Always True in `openai` mode, because startup checks it.
  - `limits_for(provider) -> Limits`: `CLOUD_LIMITS` when `provider.key == "openai"`, else `LOCAL_LIMITS`
  - `default_limits() -> Limits`: `CLOUD_LIMITS` when `openai_default()`, else `LOCAL_LIMITS`
- Produces, in `config.py`: `escalation_model` from `BT_ESCALATION_MODEL`, default `"gpt-5.6-terra"`. `openai_model` keeps its `gpt-5.6-luna` default. `llm_provider` and `validate_llm()` are unchanged.
- Produces, in `router.py`:
  - `Provider.tier: str`, one of `default`, `escalation`, `local`. `Provider.key` stays `ollama` or `openai`, because transcripts and the Mac app read it as `compute`.
  - `_provider(tier: str) -> Provider`: `default` uses `CONFIG.openai_model`, `escalation` uses `CONFIG.escalation_model`, `local` uses Ollama.
  - `LLMResponse.model: str = ""`, set from `Provider.model`.
  - `class ModelUnavailable(Exception)` with `user_message: str`. It subclasses `Exception`, not `RuntimeError`, because `gateway.chat` maps `RuntimeError` to 409 busy.
  - Copy constants `UNREACHABLE`, `LOCAL_ERROR`, `EMPTY_REPLY`, `NO_CLOUD`.
- `completion_kwargs` keeps its signature. For `openai` it sets `max_completion_tokens = CLOUD_LIMITS.max_output_tokens` and `reasoning_effort = TEXT_EFFORT[provider.tier]`. For Ollama it sets `max_tokens = LOCAL_LIMITS.max_output_tokens` and no effort.
- The `done` frame gains `"model"`. The Mac app's decoder ignores unknown keys.
- `/ready` and `/config` stay as PR #17 left them. `/ready` never contacts Ollama in `openai` mode, and `/config` already reports `provider` and `model`. `/dev/config` adds `escalation_model`. Neither returns the key.

Routing rules:

| Situation | Tier |
|---|---|
| `provider="local"` | local |
| `provider="cloud"` | escalation. With no key (`ollama` mode only): `ModelUnavailable(NO_CLOUD)` |
| Escalation phrase and `cloud_configured()` | escalation |
| Escalation phrase, no key | local; log `escalation phrase ignored: cloud unavailable` |
| Otherwise | default in `openai` mode, local in `ollama` mode |
| A cloud call fails (`APIError` or `ValueError`) | raise. No switch to local, in either mode (PR #17). |
| A cloud call returns a degenerate reply | return it when `strip_thinking` leaves text; otherwise `_result` raises as it does now. No retry. |
| The local call fails, key set | default, as now |
| The local call fails, no key | `ModelUnavailable`: `UNREACHABLE` for `APIConnectionError`, `EMPTY_REPLY` for `ValueError`, `LOCAL_ERROR` for other `APIError` |
| Degenerate local reply, key set | default, once, as now |
| Degenerate local reply, no key | return it when text is left. When none is left, retry once with `tool_choice="none"`, then `ModelUnavailable(EMPTY_REPLY)` |

Switching tiers can only go from local to a cloud tier. It keeps the tool turns so far and stops streaming deltas, as escalation does now. Each tier is entered at most once per turn, and switches don't count as tool rounds. The round budget is `limits_for(current).tool_rounds`, read again after every switch.

Fixed copy:
- `UNREACHABLE = "BT's local model isn't responding. Check that Ollama is running, then try again."`
- `LOCAL_ERROR = "BT's local model returned an error. Try again."`
- `EMPTY_REPLY = "BT's model gave an empty reply. Try again."`
- `NO_CLOUD = "The cloud model isn't set up. Add OPENAI_API_KEY on the server to use it."`

- [ ] **Step 1: Write the failing tests**

`conftest.py` keeps PR #17's `BT_LLM_PROVIDER=ollama`. OpenAI-mode tests use the existing `openai_mode` fixture in `test_router.py`, or `replace(CONFIG, llm_provider='openai', openai_api_key='test-key')`. No-key tests use `replace(CONFIG, openai_api_key='')` in `ollama` mode.

`test_tiers.py`:
- `test_limits_follow_the_provider`: `limits_for` gives `CLOUD_LIMITS` for key `openai` and `LOCAL_LIMITS` for `ollama`. `default_limits()` follows `BT_LLM_PROVIDER`.
- `test_blank_key_is_not_configured`: `cloud_configured()` is False for `None`, `''` and `'   '`.

`test_router.py`: change the `providers` fixture to key replies by tier (`default`, `escalation`, `local`) and to record `(tier, messages)`. Keep PR #17's `openai_mode` tests passing, updating them only for the tier names:
- `test_openai_default_never_touches_ollama`: also assert `model == CONFIG.openai_model`.
- `test_openai_default_errors_propagate_without_local_retry` and `test_openai_default_degenerate_reply_is_not_retried` stay as they are.
- `test_escalation_phrase_goes_to_terra`: in `openai` mode, `'think harder'` is answered by `escalation`.
- `test_openai_failure_after_a_tool_does_not_rerun_it`: in `openai` mode, `default` asks for one tool call, then raises `APIConnectionError`. The error propagates, `dispatch_call` ran once, and `local` was never called.
- `test_tool_rounds_follow_the_tier`: a tool call on every round with distinct arguments. In `openai` mode, `CLOUD_LIMITS.tool_rounds + 1` calls; in `ollama` mode with no key, `LOCAL_LIMITS.tool_rounds + 1`. This replaces `test_tool_budget_final_call_forbids_more_tools`.

In `ollama` mode with no key (`replace(CONFIG, openai_api_key='')`):
- `test_escalation_phrase_without_cloud_stays_local`: `respond([], 'try this again')` returns the local reply.
- `test_cloud_request_without_key_says_so`: `provider='cloud'` raises `ModelUnavailable` with `NO_CLOUD`.
- `test_unreachable_local_without_cloud_names_ollama`: `UNREACHABLE`.
- `test_degenerate_local_reply_without_cloud_is_returned`: `"I don't know"` comes back as the answer.
- `test_empty_local_reply_retries_once_without_cloud`: replies `'<think>x</think>'` then `'Here.'` give `'Here.'`, and the second call had `tool_choice == 'none'`. Two empty replies give `EMPTY_REPLY` after exactly two calls.

`test_streaming.py`: `completion_kwargs` for a `default` openai provider has `reasoning_effort == 'low'` and `max_completion_tokens == 8192`. For `escalation` it has `'medium'`. For Ollama it has `max_tokens == 2048` and no `reasoning_effort`.

`test_telemetry.py`: `usage(SimpleNamespace(prompt_tokens=10, completion_tokens=2, prompt_tokens_details=SimpleNamespace(cached_tokens=8)))` records `cached_tokens == 8`. A call on Luna reports `output_limit == 8192`.

`test_gateway.py`: `/dev/config` includes `escalation_model`, and no value equals the key. PR #17's readiness and config tests stay as they are.

`test_chat_ws.py`:
- `test_unavailable_model_message_reaches_the_client`: the fake `respond` raises `ModelUnavailable(router.UNREACHABLE)`. The error frame is `{'type': 'error', 'message': router.UNREACHABLE}`.
- The `done` frame carries `model`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_tiers.py tests/test_router.py tests/test_streaming.py tests/test_telemetry.py tests/test_chat_ws.py tests/test_gateway.py`
Expected: FAIL. `bt.llm.tiers` and `ModelUnavailable` don't exist, and escalation still uses `CONFIG.openai_model`.

- [ ] **Step 3: Implement**

- `tiers.py`: constants and the four functions above. No module state.
- `router.py`: implement the routing table. Drop the `# WARN` comment and `MAX_TOOL_ITERATIONS`.
- `chat_ws.run_turn` and `gateway.chat`: use `exc.user_message` in place of `FAILED` when `exc` is a `ModelUnavailable`. The diagnostics branch still logs only the error type.
- `.env.example`: add `BT_ESCALATION_MODEL=gpt-5.6-terra` under `BT_OPENAI_MODEL`.
- `docs/DESIGN.md`: replace the routing section with `BT_LLM_PROVIDER`, the three tiers, and the note that every transcript still records which backend answered. Update the README's "Model routing" section to name Terra as the escalation model.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/llm server/bt/config.py server/bt/gateway server/bt/devui/routes.py server/tests server/.env.example docs/DESIGN.md README.md
git commit -m "feat: add Terra escalation and per-tier limits"
```

---

### Task 2: Model tiers for voice

Voice has its own model path (`bt/voice/routing.py`; see AGENTS.md). `RoutedLLMService` is an Ollama service with an optional cloud service, so Qwen is `self`. PR #17 already starts voice on `_cloud` (Luna) in `openai` mode. This task adds a Terra service for escalation, voice reasoning effort and per-tier history limits. Voice uses lower reasoning effort than text, so the first spoken word isn't held up.

**Files:**
- Modify: `server/bt/voice/routing.py` (`RoutedLLMService`, `_trim`, `get_chat_completions`, `_refresh_prompt`, `cleanup`)
- Test: `server/tests/test_voice_routing.py`

**Interfaces:**
- Consumes: `CLOUD_LIMITS`, `LOCAL_LIMITS`, `VOICE_EFFORT`, `openai_default`, `cloud_configured`, `limits_for` (Task 1).
- Produces:
  - `RoutedLLMService._cloud` (Luna) and `RoutedLLMService._escalation` (Terra), both `CloudLLMService` or `None` without a key. Each is built with `OpenAILLMService.Settings(model=..., system_instruction=system, max_completion_tokens=CLOUD_LIMITS.max_output_tokens, extra={"reasoning_effort": VOICE_EFFORT[tier]})`. Pipecat merges `Settings.extra` into the request (`services/openai/base_llm.py`).
  - `_trim(context: LLMContext, budget: int) -> None`. The module constant `MAX_HISTORY_CHARS` goes away.
  - `VOICE_UNAVAILABLE = "I can't reach my model right now."`

Rules:
- Provider order:
  - escalation phrase with a key: `[_escalation]`
  - `openai` mode: `[_cloud]`
  - `ollama` mode with a key: `[self, _cloud]`
  - `ollama` mode without a key: `[self]`
- `_trim(context, limits.history_chars)` for the first provider before its call. A fallback only goes from Qwen to the cloud, so it never needs a smaller trim.
- A cloud failure raises, before or after the first chunk. It is never retried on Qwen (PR #17). `compute` is `openai` for both cloud services.
- When Qwen is the last provider and fails before emitting anything (`ollama` mode without a key): log `voice reply failed error_type=%s`, push `TTSSpeakFrame(VOICE_UNAVAILABLE, append_to_context=False)`, and end the stream without raising. A failure after text was emitted still raises, so a partial answer is never repeated.
- `/no_think` stays on Qwen's prompt only. `_refresh_prompt` and `cleanup` cover all three services.

- [ ] **Step 1: Write the failing tests**

- `test_voice_escalation_phrase_uses_terra`: in both modes with a key.
- `test_voice_escalation_phrase_without_cloud_stays_local`.
- `test_voice_failure_without_cloud_speaks_a_line`: `ollama` mode, no key (`openai_api_key=''`), and a local stream that raises before any text. Consuming the stream yields no chunks and doesn't raise. A spy on `push_frame` got one `TTSSpeakFrame` with `VOICE_UNAVAILABLE` and `append_to_context=False`.
- `test_voice_cloud_history_uses_cloud_limits`: in `openai` mode, 100,000 characters of history reach Luna untrimmed.
- `test_voice_cloud_services_get_voice_effort`: `_cloud._settings.extra == {'reasoning_effort': 'none'}` and `_escalation`'s is `'low'`.
- Update the two `_trim` tests to pass `LOCAL_LIMITS.history_chars`. Keep PR #17's `openai_mode` voice tests and `test_voice_does_not_repeat_answer_after_partial_stream_failure` as they are.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_voice_routing.py`
Expected: FAIL. There is no Terra service, and `_trim` takes no budget.

- [ ] **Step 3: Implement** the rules above in `routing.py`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Manual check**

In `openai` mode, run `make server`, start a voice session, and ask a question: `make logs` shows `compute=openai`. Say "think harder": the log names Terra. Restart with `BT_LLM_PROVIDER=ollama`, no key and Ollama stopped: BT says "I can't reach my model right now."

- [ ] **Step 6: Commit**

```bash
git add server/bt/voice/routing.py server/tests/test_voice_routing.py
git commit -m "feat: add Terra escalation and per-tier limits to voice"
```

---

### Task 3: Tool error codes, schema on bad arguments, error counts

**Files:**
- Modify: `server/bt/tools/registry.py` (`run_tool`, `dispatch_call`)
- Modify: `server/bt/llm/router.py` (tool loop, around line 200)
- Modify: `server/bt/llm/telemetry.py` (`TurnMetrics`)
- Modify: `server/bt/gateway/chat_ws.py` (`call_client` return strings)
- Test: `server/tests/test_registry.py`, `server/tests/test_router.py`, `server/tests/test_telemetry.py`, `server/tests/test_chat_ws.py`

**Interfaces:**
- Produces, in `registry.py`:
  - `class ToolErrorCode(StrEnum)` with `UNKNOWN_TOOL, INVALID_JSON, INVALID_ARGS, MISSING_ARGS, TIMEOUT, REJECTED, FAILED, BAD_RESULT, CLIENT_FAILED`. Tasks 4 and 5 add `SURFACE_NOT_ALLOWED` and `LOOP_DETECTED`.
  - `tool_error(code: ToolErrorCode, message: str, spec: ToolSpec | None = None) -> str`
  - `error_code(text: str) -> str | None`
- Produces, in `telemetry.py`: `TurnMetrics.tool_error(code: str) -> None`. `snapshot()` gains `"tool_errors": dict[str, int]`.

- [ ] **Step 1: Write the failing tests**

In `test_registry.py`, rewrite the two existing tests' expectations and add one:

```python
def test_errors_carry_codes_and_schema(monkeypatch):
    _with_tool(monkeypatch)
    ctx = _ctx()
    missing = asyncio.run(registry.dispatch_call('echo', '{}', ctx))
    assert missing.startswith('Error MISSING_ARGS: echo requires query.')
    assert 'Expected arguments: {"properties":{"query":{"type":"string"}},"required":["query"]}' in missing
    assert asyncio.run(registry.dispatch_call('echo', '{bad', ctx)).startswith('Error INVALID_JSON:')
    assert asyncio.run(registry.dispatch_call('echo', '[1]', ctx)).startswith('Error INVALID_ARGS:')
    unknown = asyncio.run(registry.dispatch_call('nope', '{}', ctx))
    assert unknown == 'Error UNKNOWN_TOOL: No tool named nope is available. Available tools: echo.'
    assert registry.error_code(missing) == 'MISSING_ARGS'
    assert registry.error_code('got hi') is None
```

In `test_telemetry.py`: `TurnMetrics('t').tool_error('TIMEOUT')` twice, then `snapshot()['tool_errors'] == {'TIMEOUT': 2}`. A fresh `TurnMetrics` snapshot has `tool_errors == {}`.

In `test_router.py`: `test_tool_errors_are_counted`. Monkeypatch `dispatch_call` to return `'Error TIMEOUT: x'` once, then a plain reply. Pass `telemetry=TurnMetrics('t')`. Assert `telemetry.snapshot()['tool_errors'] == {'TIMEOUT': 1}`.

In `test_chat_ws.py`: change the expected text in `test_failed_client_tool_is_reported_to_the_model` to `'Error CLIENT_FAILED: calendar_list_events failed: Calendar access is off'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_registry.py tests/test_telemetry.py tests/test_router.py tests/test_chat_ws.py`
Expected: FAIL. `ToolErrorCode`, `error_code` and `tool_error` don't exist, and the old error strings don't match.

- [ ] **Step 3: Implement**

- `tool_error` returns `f"Error {code}: {message}"`.
  - For `MISSING_ARGS`, `INVALID_JSON` and `INVALID_ARGS` with a `spec`, append ` Expected arguments: ` + `json.dumps({"properties": spec.properties, "required": list(spec.required)}, separators=(",", ":"))`.
  - `UNKNOWN_TOOL` messages end with `Available tools: <comma-joined sorted names>.`
- `error_code` matches `^Error ([A-Z_]+): `.
- Every early return in `run_tool` and `dispatch_call` goes through `tool_error`. Keep each current sentence as the message:
  - timeout → `TIMEOUT`
  - `ValueError` → `REJECTED`
  - other exceptions → `FAILED`
  - non-str result → `BAD_RESULT`
- Each `tool_error` call also logs `log.warning("tool_error tool=%s code=%s", name, code)` and nothing else.
- `call_client` timeout returns `tool_error(TIMEOUT, ...)`. Failure returns `tool_error(CLIENT_FAILED, f"{name} failed: {result.content}")`.
- Router: after each tool result, `if telemetry and (code := error_code(content)): telemetry.tool_error(code)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass. Fix any other test that pinned an old error sentence by adding the `Error <CODE>: ` prefix.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tools/registry.py server/bt/llm/router.py server/bt/llm/telemetry.py server/bt/gateway/chat_ws.py server/tests
git commit -m "feat: give tool errors codes, schemas and counts"
```

---

### Task 4: Fixed tool list with a call-time surface check

The tool list is already fixed per connection. `chat_ws` rejects a second `hello`, and voice builds `pipecat_tools()` once. This task pins that with a test and adds the call-time check Task 8 needs: some tools are declared on every surface but refused on voice, so the list never varies.

**Files:**
- Modify: `server/bt/tools/registry.py` (`ToolSpec`, `tool`, `run_tool`, `manifest_lines`)
- Modify: `AGENTS.md` (Learned mistakes/behaviors)
- Test: `server/tests/test_registry.py`

**Interfaces:**
- Consumes: `tool_error`, `ToolErrorCode` (Task 3).
- Produces:
  - `ToolSpec.surfaces: frozenset[str] = frozenset(SURFACES)`, added as the last field so positional construction in tests still works.
  - `tool(..., surfaces: tuple[str, ...] = SURFACES)`.
  - `ToolErrorCode.SURFACE_NOT_ALLOWED`.
  - `authorize(spec: ToolSpec, ctx: ToolContext) -> str | None` returns error text or `None`.

- [ ] **Step 1: Write the failing tests**

```python
def test_text_only_tool_is_declared_everywhere_but_refused_on_voice(monkeypatch):
    spec = registry.ToolSpec('wipe', 'Wipe.', {}, (), _echo_none, 'You can wipe.', 1.0, frozenset({'text'}))
    monkeypatch.setattr(registry, '_REGISTRY', {'wipe': spec})
    monkeypatch.setattr(registry, 'load_builtins', lambda: None)
    assert [t['function']['name'] for t in registry.openai_tools()] == ['wipe']
    voice = SimpleNamespace(used=[], surface='voice')
    assert asyncio.run(registry.dispatch_call('wipe', '{}', voice)).startswith('Error SURFACE_NOT_ALLOWED:')
    assert registry.manifest_lines('voice', skills=_no_skills()) == []
    assert registry.manifest_lines('text', skills=_no_skills()) == ['You can wipe.']

def test_tool_list_is_identical_across_calls_and_surfaces():
    first = registry.openai_tools()
    assert registry.openai_tools() == first
    assert [s.name for s in registry.pipecat_tools()] == [t['function']['name'] for t in first]
```

`_echo_none` is an async handler returning `'done'`. `_no_skills()` returns `SimpleNamespace(manifest=lambda surface: [])`. The `_ctx()` helper gains `surface='text'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_registry.py`
Expected: FAIL. `ToolSpec` takes 7 positional arguments, and voice runs the tool.

- [ ] **Step 3: Implement**

- `authorize` returns `tool_error(SURFACE_NOT_ALLOWED, f"{spec.name} is only available in text chat.")` when `ctx.surface not in spec.surfaces`.
- `run_tool` calls `authorize` first, before the required-argument check.
- `manifest_lines(surface)` skips specs whose `surfaces` exclude `surface`.
- `openai_tools` and `pipecat_tools` stay unfiltered.
- Add this line to AGENTS.md "Learned mistakes/behaviors": `- Never vary the tool list per turn or per surface; it breaks Ollama's prompt cache. Declare every tool once and refuse at call time in registry.authorize (surfaces=, loop guard).`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tools/registry.py server/tests/test_registry.py AGENTS.md
git commit -m "feat: check tool surface at call time, keep tool list fixed"
```

---

### Task 5: Loop guard

**Files:**
- Create: `server/bt/tools/loop_guard.py`
- Modify: `server/bt/tools/registry.py` (`ToolContext.guard`, Pipecat `bridge` in `_function_schema`)
- Modify: `server/bt/llm/router.py` (tool loop)
- Modify: `server/bt/voice/persist.py` (`TranscriptObserver`), `server/bt/voice/pipeline.py` (`build_worker`)
- Test: `server/tests/test_loop_guard.py` (new), `server/tests/test_router.py`, `server/tests/test_voice_pipeline.py`

**Interfaces:**
- Consumes: `tool_error` (Task 3). Adds `ToolErrorCode.LOOP_DETECTED`.
- Produces, in `loop_guard.py`:
  - `@dataclass class LoopGuard` with:
    - `check(self, name: str, arguments: str | None) -> str | None` returns a block reason or `None`
    - `record(self, name: str, arguments: str | None, result: str) -> None`
    - `reset(self) -> None`
    - `tripped: bool`
  - Constants: `REPEAT_LIMIT = 2`, `WINDOW_SIZE = 6`, `WINDOW_DISTINCT_LIMIT = 2`.
  - `fingerprint(name: str, arguments: str | None) -> str`, public because Task 13 reuses it.
- Produces: `ToolContext.guard: LoopGuard = field(default_factory=LoopGuard)`. `TranscriptObserver(..., on_user_turn: Callable[[], None] | None = None)`.

Rules (Cindy's layers 1 and 2, scaled to BT's small deterministic tool set):
- Fingerprint = `name + "\x00" + canonical arguments`. Canonical arguments: `json.dumps(json.loads(arguments or "{}"), sort_keys=True)`, falling back to the raw string if it isn't valid JSON. Result digest = `hashlib.sha1(result.encode()).hexdigest()`.
- **Repeat:** block when the last `REPEAT_LIMIT` records share this fingerprint and have equal result digests.
- **Ping-pong:** block when this fingerprint plus the last `WINDOW_SIZE - 1` records span at most `WINDOW_DISTINCT_LIMIT` distinct fingerprints.
- Blocked calls are not recorded, and they set `tripped = True`. Reasons:
  - Repeat: `"{name} already ran with these arguments and returned the same result. Answer with what you have."`
  - Ping-pong: `"Tool calls are repeating. Answer with what you have."`

- [ ] **Step 1: Write the failing tests**

`test_loop_guard.py`:
- `test_third_identical_call_is_blocked`: record `('memory_search', '{"query":"x"}', 'r')` twice. `check` with the same arguments returns the repeat reason, and `tripped` is True.
- `test_key_order_does_not_dodge_the_guard`: record `'{"a":1,"b":2}'` twice. `check('t', '{"b":2,"a":1}')` blocks.
- `test_same_call_with_new_result_is_allowed`: record the same call with results `'r1'`, `'r2'`. `check` returns `None`.
- `test_ping_pong_is_blocked`: record A, B, A, B, A, each with distinct results. `check(B)` returns the ping-pong reason.
- `test_reset_clears_history`: after the repeat setup, `reset()`, then `check` is `None` and `tripped` is False.

`test_router.py`:
- `test_repeated_tool_call_forces_an_answer`: `_complete` always returns the same tool call. A `dispatch_call` spy counts runs and returns `'nothing'`. Assert the spy ran 2 times, `len(seen) == 4`, and `seen[-1][1] == 'none'`.
- `test_tool_rounds_follow_the_tier` (Task 1) already gives each round distinct arguments, so it keeps testing the budget with the guard in place.
- `test_repeated_client_tool_is_blocked`: same as the first, through `call_client`. The client function runs 2 times.

`test_voice_pipeline.py`:
- `test_user_turn_resets_loop_guard`: build `TranscriptObserver(store, sid, {}, on_user_turn=spy)`, push a `TranscriptionFrame` from an `STTService` source, and assert the spy was called once.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_loop_guard.py tests/test_router.py tests/test_voice_pipeline.py`
Expected: FAIL. `bt.tools.loop_guard` is missing, and the observer doesn't accept `on_user_turn`.

- [ ] **Step 3: Implement**

- `router.py`:
  - Keep Task 1's `limits_for(current).tool_rounds` as the round budget.
  - In `respond`, create `guard = LoopGuard()` per call, so text is turn-scoped and test contexts stay `SimpleNamespace`.
  - Around each tool call (server and client): if `reason := guard.check(name, arguments)`, use `tool_error(LOOP_DETECTED, reason)` as the content without running the tool. Otherwise run it, then `guard.record(...)`.
  - After the round, if `guard.tripped`, return `_result(await complete(tool_choice="none"), current, ctx)`.
- `registry.py`: the Pipecat `bridge` does the same check and record with `ctx.guard`, using `json.dumps(params.arguments)` as the arguments string.
- `persist.py`: call `on_user_turn()` on a user `TranscriptionFrame`, before `_add_turn`.
- `pipeline.py`: hold `ctx = default_context(session_id, "voice") if tools else None`, pass it as `app_resources`, and pass `on_user_turn=ctx.guard.reset if ctx else None` to the observer.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tools server/bt/llm/router.py server/bt/voice server/tests
git commit -m "feat: stop repeated tool calls with a loop guard"
```

---

### Task 6: FTS5 memory search

**Files:**
- Modify: `server/bt/library.py` (`MemoryStore.search`, `_all` cache; remove `_score` and `_WEIGHTS`)
- Test: `server/tests/test_library.py`

**Interfaces:**
- Produces:
  - `fts_query(text: str) -> str | None` in `library.py`: the existing word filter (`_WORDS`, length > 2, not in `_FILLER`), each word wrapped in double quotes and joined with ` OR `. Returns `None` when no words are left. Task 7 reuses it.
  - `MemoryStore.search(query: str, limit: int = 5) -> list[Memory]`, same signature as now.

- [ ] **Step 1: Write the failing tests**

- `test_search_matches_whole_words_only`: memory `car-park` (body "the car is on level 2") and memory `winter-kit` (body "blue scarf"). `[m.name for m in search('car')] == ['car-park']`. Today's substring count also returns `winter-kit`.
- `test_search_matches_word_stems`: body "the boiler needs servicing", and `search('service')` finds it. This already passes through the fuzzy fallback; it pins the behavior.
- `test_name_match_outranks_body_match`: memory `coffee-order` (description about drinks) and memory `notes` whose body mentions coffee once. `search('coffee')[0].name == 'coffee-order'`.
- `test_search_survives_fts_syntax`: `search('"NEAR(* -')` returns `[]` without raising. `fts_query('the and')` is `None`.
- `test_search_sees_new_memory_without_restart`: write, search, write a second memory, then search finds the second.
- Keep the existing fuzzy-typo and filler tests unchanged. They must still pass.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_library.py`
Expected: FAIL. `test_search_matches_whole_words_only` also returns `winter-kit`, and `fts_query` doesn't exist.

- [ ] **Step 3: Implement**

- Build a private in-memory index: `sqlite3.connect(":memory:", check_same_thread=False)` with `CREATE VIRTUAL TABLE memories USING fts5(name, description, body, tokenize='porter unicode61')`, and `rowid` = position in the `_all()` list.
- Rebuild it whenever `_all()` reparses (same mtime key). Guard it with a `threading.Lock`, because text and voice both search.
- Query: `SELECT rowid FROM memories WHERE memories MATCH ? ORDER BY bm25(memories, 3.0, 2.0, 1.0) LIMIT ?`.
- No hits: keep the existing `_fuzzy_score` fallback, since it catches voice typos FTS can't.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q tests/test_library.py tests/test_builtin_tools.py tests/test_system_prompt.py`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/library.py server/tests/test_library.py
git commit -m "feat: rank memory search with SQLite FTS5"
```

---

### Task 7: Past-session search

**Files:**
- Modify: `server/bt/transcript/store.py` (schema, `__init__`, new `search_turns`)
- Modify: `server/bt/tools/registry.py` (`ToolContext.transcript`, `default_context`)
- Modify: `server/bt/tools/builtin.py` (new `session_search` tool)
- Test: `server/tests/test_store.py`, `server/tests/test_builtin_tools.py`

**Interfaces:**
- Consumes: `fts_query` (Task 6).
- Produces:
  - `@dataclass(frozen=True) class TurnHit: session_id: str; ts: float; role: str; snippet: str` in `store.py`.
  - `TranscriptStore.search_turns(self, query: str, *, exclude_session: str | None = None, limit: int = 5) -> list[TurnHit]`.
  - `ToolContext.transcript: TranscriptStore | None = None`, which `default_context` sets to `get_store()`.
  - Tool `session_search(query: str)`, timeout 5s, both surfaces. Manifest: `"You can search past conversations with session_search."`

- [ ] **Step 1: Write the failing tests**

`test_store.py`:
- `test_search_finds_turns_in_other_sessions`: two sessions. Session A has "the boiler needs servicing". `search_turns('boilers', exclude_session=B)` returns one hit with `session_id == A`, `role == 'user'`, and "boiler" in the snippet.
- `test_search_excludes_current_session`: same text only in B. `search_turns('boiler', exclude_session=B) == []`.
- `test_existing_database_is_backfilled`: create a `tmp_path` DB with the pre-FTS schema and one turn using raw `sqlite3`, open `TranscriptStore` on it, and the search finds that turn.
- `test_search_with_only_filler_returns_nothing`: `search_turns('what is the') == []`.

`test_builtin_tools.py`:
- `test_session_search_reports_dates_and_speakers`: a context whose `transcript` holds a past user turn. Result starts `'From past conversations.'` and contains `'the Pilot said'`.
- No hits: the result equals `'No past conversation mentions boiler.'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_store.py tests/test_builtin_tools.py`
Expected: FAIL. `search_turns` and `session_search` don't exist.

- [ ] **Step 3: Implement**

- Add to `SCHEMA`:
  - `CREATE VIRTUAL TABLE IF NOT EXISTS turns_fts USING fts5(text, content='turns', content_rowid='rowid', tokenize='porter unicode61')`
  - `AFTER INSERT` and `AFTER DELETE` triggers on `turns`. The delete trigger uses `INSERT INTO turns_fts(turns_fts, rowid, text) VALUES('delete', old.rowid, old.text)`.
- In `__init__`, check `sqlite_master` for `turns_fts` before `executescript`. If it was missing, run `INSERT INTO turns_fts(turns_fts) VALUES('rebuild')` after.
- `search_turns`:
  - Return `[]` when `fts_query` returns `None`.
  - Join `turns` on rowid, `WHERE turns_fts MATCH ? AND t.session_id IS NOT ?`, `ORDER BY bm25(turns_fts)`.
  - Snippet: `snippet(turns_fts, 0, '', '', '…', 16)`.
  - Run under `_lock`.
- Tool output: `"From past conversations. " + " ".join(f"On {date:%d %B %Y} {who}: {snippet}.")`, where `who` is `the Pilot said` for `user` and `you said` for `bt`. Call through `asyncio.to_thread`, excluding `ctx.session_id`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/transcript/store.py server/bt/tools server/tests
git commit -m "feat: search past conversations with FTS5"
```

---

### Task 8: Memory upkeep tools

**Files:**
- Modify: `server/bt/library.py` (`MemoryStore.write` hard limit, new `size_warnings`, `delete`, `consolidate`)
- Create: `server/bt/tools/memory_upkeep.py` (`memory_delete`, `memory_consolidate`, `memory_review`)
- Modify: `server/bt/tools/registry.py` (`load_builtins` also imports `memory_upkeep`)
- Modify: `server/bt/tools/builtin.py` (`memory_write` appends warnings)
- Modify: `server/bt/llm/router.py` (new `one_shot`)
- Test: `server/tests/test_library.py`, `server/tests/test_memory_upkeep.py` (new)

**Interfaces:**
- Consumes: `surfaces=` and `SURFACE_NOT_ALLOWED` (Task 4).
- Produces, in `library.py`:
  - Constants `BODY_SOFT_CHARS = 1500`, `BODY_HARD_CHARS = 6000`. The index soft limit reuses `INDEX_LIMIT = 60`.
  - `MemoryStore.size_warnings(self, memory: Memory) -> list[str]`
  - `MemoryStore.delete(self, name: str) -> bool`
  - `MemoryStore.consolidate(self, sources: list[str], name: str, description: str, body: str, type: str = "user") -> Memory`
- Produces, in `router.py`: `async def one_shot(system: str, user: str) -> str`. No tools. It calls the default tier (Luna) in `openai` mode and Qwen in `ollama` mode, with `user` cut to its last `LOCAL_LIMITS.history_chars` characters for Qwen. A failure raises; it never switches models (PR #17). It returns `strip_thinking` text. Tasks 11 and 17 reuse it.
- Tools:
  - `memory_delete(name)`: text only.
  - `memory_consolidate(sources: array[string], name, description, body, type)`: text only.
  - `memory_review()`: text only, timeout 30s.
  - One manifest, on `memory_review`: `"You can tidy memories with memory_review, memory_consolidate and memory_delete. Ask the Pilot before deleting or merging."`

Fixed copy:
- Long-body warning: `"This memory is long ({n} characters); trim it or split it."`
- Index warning: `"There are {n} memories, more than the {INDEX_LIMIT} listed in your prompt; merge related ones with memory_consolidate."`
- Hard limit `ValueError`: `"a memory body is limited to 6000 characters"`.
- Review system prompt: `"You review a list of stored memories. Point out duplicates to merge, contradictions, and entries that look out of date. Name the memories involved. Reply with at most five short lines. If nothing needs changing, reply: No changes needed."`
- Review result: `"Memory review suggestions. {text} Ask the Pilot before deleting or merging."`
- Empty store: `"There are no stored memories to review."`

- [ ] **Step 1: Write the failing tests**

`test_library.py`:
- `test_write_rejects_huge_body`: a 6001-character body raises `ValueError`.
- `test_size_warnings`: a 1501-character body gives exactly the long-body warning. 61 memories give the index warning.
- `test_delete_removes_file_and_index_line`: `delete` returns True, then False the second time. The name is gone from `MEMORY.md`.
- `test_consolidate_keeps_target_listed_as_source`: sources `['a', 'b']`, target `'a'`. Afterwards `a` holds the new body and `b` is gone.
- `test_consolidate_with_unknown_source_changes_nothing`: sources `['a', 'missing']` raises `ValueError`. `a` and the index are unchanged.

`test_memory_upkeep.py`:
- `memory_delete` on a voice context returns a `SURFACE_NOT_ALLOWED` error.
- `test_one_shot_follows_the_provider`: in `openai` mode `default` answers. When it raises `APIConnectionError`, the error propagates and `local` is never called. In `ollama` mode the local call gets a user message cut to `LOCAL_LIMITS.history_chars`.
- `memory_review` with `router.one_shot` monkeypatched to return `'Merge a and b.'` returns the review result copy around that text.
- `memory_review` on an empty store returns the empty copy without calling `one_shot`.
- `memory_write` with a 1501-character body returns `"Saved as x. This memory is long (1501 characters); trim it or split it."`

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_library.py tests/test_memory_upkeep.py`
Expected: FAIL on the missing methods and tools.

- [ ] **Step 3: Implement**

- `consolidate`:
  1. Check every source exists before touching anything.
  2. `write` the target.
  3. Unlink each source whose slug differs from the target slug.
  4. `write_index()`.
- `memory_review` input: one line per index memory, `name (type, updated): description — first 300 chars of body`.
- Import `one_shot` inside the handler to avoid a `router` ↔ `registry` import cycle.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/library.py server/bt/tools server/bt/llm/router.py server/tests
git commit -m "feat: add memory delete, consolidate and review tools"
```

---

### Task 9: Warning before the context window fills

Text path only. Voice turns pick up the nudge when a text turn in the same session has recorded pressure. See "Not in this plan".

**Files:**
- Create: `server/bt/llm/context_watch.py`
- Modify: `server/bt/llm/telemetry.py` (extract `context_limit_for`; `CallMetrics.snapshot` adds `context_ratio`)
- Modify: `server/bt/llm/router.py` (`complete()` inside `respond`)
- Modify: `server/bt/personality/system_prompt.py` (`turn_note`)
- Test: `server/tests/test_context_watch.py` (new), `server/tests/test_system_prompt.py`, `server/tests/test_router.py`

**Interfaces:**
- Produces, in `context_watch.py`:
  - `THRESHOLDS = (0.70, 0.85, 0.92)`, `NUDGE_AT = 0.85`
  - `record(session_id: str, prompt_tokens: int, limit: int) -> float | None` returns the highest newly crossed threshold. It logs once per threshold per session, and clears that session's fired set when the ratio drops below `0.70`.
  - `nudge(session_id: str) -> str | None`
  - `reset_all() -> None`, for tests.
- Produces, in `telemetry.py`: `context_limit_for(provider) -> int | None`. This is the matching rule already in `CallMetrics.__init__`, moved out.
- Log line: `log.warning("context_pressure session=%s threshold=%.2f prompt_tokens=%d limit=%d", ...)`.
- Nudge copy: `"Context is {pct}% full and older turns will soon drop out. Save anything worth keeping with memory_write now."`, where `pct = int(ratio * 100)`.

- [ ] **Step 1: Write the failing tests**

`test_context_watch.py` (call `reset_all()` in a fixture):
- `test_each_threshold_fires_once`: records at 2900, 2950 and 3500 of 4096 return `0.70`, `None`, `0.85`.
- `test_jump_reports_highest_and_marks_lower`: 3800 of 4096 returns `0.92`, then 2900 returns `None`.
- `test_drop_below_lowest_rearms`: 3500, then 1000, then 3500 returns `0.85` again.
- `test_nudge_starts_at_085`: 3400 of 4096 gives `nudge` = `None`. 3500 gives `'Context is 85% full and older turns will soon drop out. Save anything worth keeping with memory_write now.'`.

`test_system_prompt.py`: after `context_watch.record('s', 3500, 4096)`, `turn_note('hi', session_id='s')` ends with the nudge. `turn_note('hi', session_id='other')` doesn't contain it.

`test_router.py`:
- `test_context_watch_off_without_limit`: no `BT_CONTEXT_LIMIT` (the conftest default), with a spy on `context_watch.record`. One `respond` makes zero `record` calls, and `_complete` is called without a `metrics` kwarg.
- `test_context_watch_records_prompt_tokens`: monkeypatch `router.context_limit_for` to return 4096, and have the fake `_complete(..., metrics=None)` call `metrics.usage(SimpleNamespace(prompt_tokens=3500, completion_tokens=5))`. Assert `record` was called with `(sid, 3500, 4096)`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_context_watch.py tests/test_system_prompt.py tests/test_router.py`
Expected: FAIL. `bt.llm.context_watch` is missing.

- [ ] **Step 3: Implement**

- In `respond`'s `complete()`:
  - With no `telemetry` but `context_limit_for(current)` returning a value, create a standalone `CallMetrics(current)` and pass it as `metrics` so usage is requested.
  - Keep `telemetry.publish()` and `tool_elapsed` behind `if telemetry`.
  - Import `context_limit_for` into `router.py` by name, so the test's monkeypatch takes effect. After finishing, if `session_id` is set, `limit := context_limit_for(current)` is set, and the call's `prompt_tokens` is known, call `context_watch.record(session_id, prompt_tokens, limit)`. Pass the router's limit directly; don't read it from `CallMetrics.values`.
- `CallMetrics.finish` sets `context_ratio = prompt_tokens / context_limit` when both are known.
- `turn_note` appends `context_watch.nudge(session_id)` when it isn't `None`.
- Mark the module-level dicts with `# ponytail: per-process dict keyed by session, never pruned; prune on session delete if sessions grow large`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Manual check**

Run `make server` with `BT_CONTEXT_LIMIT=4096 BT_CONTEXT_LIMIT_PROVIDER=ollama BT_CONTEXT_LIMIT_MODEL=qwen3:8b`. Chat until `make logs` shows a `context_pressure` line, and confirm the next reply mentions saving memories.

- [ ] **Step 6: Commit**

```bash
git add server/bt/llm server/bt/personality/system_prompt.py server/tests
git commit -m "feat: warn the model before the context window fills"
```

---

### Task 10: Tool output limits

From OpenClaw's session pruning and Hermes' first compression phase. One `calendar_list_events` over a busy month can fill Qwen's context, and a cloud turn can run 25 rounds. Two limits per tier: one per result, one per turn. Messages are never removed, only shortened, so every tool call keeps its tool message.

**Files:**
- Create: `server/bt/llm/context_budget.py`
- Modify: `server/bt/llm/router.py` (tool results, before each model call)
- Modify: `server/bt/tools/registry.py` (Pipecat `bridge`)
- Test: `server/tests/test_context_budget.py` (new), `server/tests/test_router.py`, `server/tests/test_registry.py`

**Interfaces:**
- Consumes: `Limits`, `limits_for`, `LOCAL_LIMITS` (Task 1).
- Produces, in `context_budget.py`:
  - `clip_result(text: str, limit: int) -> str`. It keeps `limit * 3 // 8` characters from each end (1,500 at Qwen's 4,000; 6,000 at the cloud's 16,000).
  - `KEEP_SHORT_CHARS = 200`, `CLEARED` (copy below)
  - `clear_old_tool_output(messages: list[dict], budget: int) -> list[dict]`
  - Task 11 adds `SUMMARY_PREFIX` and `fit_to_limits` here.

Fixed copy:
- Clip marker, between head and tail: `"\n[{cut} characters cut. Ask for less to see the rest.]\n"`
- `CLEARED = "[Old tool output cleared to save context space. Call the tool again if you need it.]"`

- [ ] **Step 1: Write the failing tests**

`test_context_budget.py`, with `_round(id, size)` building an assistant message with one tool call `id` and its tool message of `size` characters:
- `test_long_results_keep_head_and_tail`: `clip_result('a' * 3000 + 'b' * 3000, 4000)` starts with `'a' * 1500`, ends with `'b' * 1500`, and contains `'[3000 characters cut. Ask for less to see the rest.]'`. With limit 16,000, `'a' * 10000 + 'b' * 10000` keeps 6,000 from each end.
- `test_results_at_the_limit_are_unchanged`: a 4000-character text at limit 4000.
- `test_old_tool_output_is_cleared_over_budget`: system, user, `_round('c1', 8000)`, `_round('c2', 8000)` with budget 12,000. `c1`'s content becomes `CLEARED`, `c2`'s is unchanged, and the input list and its dicts are unchanged.
- `test_under_budget_nothing_changes`: two rounds of 4000 with budget 12,000.
- `test_short_and_error_results_are_kept`: rounds of 150 characters, `'Error TIMEOUT: x' + 'y' * 5000`, 8000 and 8000 with budget 12,000. Only the third round's content is cleared.
- `test_pairs_survive_clearing`: every `tool_call_id` still has exactly one tool message, and the message count is unchanged.

`test_router.py`:
- `test_client_result_is_clipped_for_the_tier`: `call_client` returns `'x' * 5000`. In `ollama` mode the next call sees `'characters cut'`. In `openai` mode it sees all 5,000 characters.

`test_registry.py`:
- `test_voice_bridge_clips_at_local_limit`: a handler returning 5,000 characters reaches `result_callback` clipped.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_context_budget.py tests/test_router.py tests/test_registry.py`
Expected: FAIL. `bt.llm.context_budget` doesn't exist.

- [ ] **Step 3: Implement**

- `clear_old_tool_output`: return the input when the total length of tool contents is at most `budget`. Otherwise build a new list. Tool messages after the last assistant message with `tool_calls` are the latest round and stay. Older tool messages longer than `KEEP_SHORT_CHARS` that don't start with `Error ` become new dicts with `content = CLEARED`.
- Router: clip every tool result, server and client, with `limits_for(current).tool_result_chars`. Before each model call after the first, rebind `working = clear_old_tool_output(working, limits_for(current).turn_tool_chars)`. `complete()` reads the enclosing `working`, so it sees the new list.
- Pipecat `bridge`: clip with `LOCAL_LIMITS.tool_result_chars`. A spoken answer never needs more.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/llm server/bt/tools/registry.py server/tests
git commit -m "feat: cap tool output per result and per turn"
```

---

### Task 11: Rolling session summary

From OpenClaw's compaction, Hermes' compression and Manus' KV-cache advice. The text path sends the last 50 turns with no size limit. On Luna that is a cost problem, and on Qwen it overflows: Ollama then drops the start of the prompt, the system prompt and tools. Once past 50 turns, the window also slides one turn per turn, so the prefix changes on every request and the cache never hits. OpenAI also charges 1.25× for each cache write.

This task folds the oldest turns into a stored summary in one step, once unsummarized history passes the default tier's `history_chars` (160,000 in `openai` mode, 16,000 in `ollama` mode). It keeps the newest half. Between compactions history only grows at the end, so the prefix stays cacheable. The raw turns stay in `turns`, and `/history` and `session_search` still see them.

Compaction runs before the model call of a text turn (Hermes' "preflight" check), inside the conversation lease. Voice gets the summary the next time it connects, because it loads history through `as_chat_messages`.

When an `openai`-mode turn is sent to Qwen with `provider="local"`, the history built for Luna can be ten times Qwen's limit. `fit_to_limits` cuts it down for that request only, keeping the summary and the current turn.

**Files:**
- Modify: `server/bt/transcript/store.py` (sessions columns, `pending_turns`, `save_summary`, `as_chat_messages`)
- Create: `server/bt/transcript/compaction.py`
- Modify: `server/bt/llm/context_budget.py` (`SUMMARY_PREFIX`, `fit_to_limits`)
- Modify: `server/bt/llm/router.py` (fit when the tier is local)
- Modify: `server/bt/gateway/chat_ws.py` (`answer`), `server/bt/gateway/gateway.py` (`chat`)
- Test: `server/tests/test_compaction.py` (new), `server/tests/test_store.py`, `server/tests/test_context_budget.py`, `server/tests/test_router.py`, `server/tests/test_chat_ws.py`

**Interfaces:**
- Consumes: `default_limits`, `LOCAL_LIMITS` (Task 1); `clear_old_tool_output` (Task 10); `one_shot` (Task 8).
- Produces, in `context_budget.py`:
  - `SUMMARY_PREFIX = "Summary of the earlier conversation, added by the system: "`
  - `fit_to_limits(messages: list[dict], limits: Limits) -> list[dict]`
- Produces, in `store.py`:
  - Columns `sessions.summary TEXT` and `sessions.summary_through INTEGER NOT NULL DEFAULT 0` (a `turns` rowid), added with `ALTER TABLE` when missing, like `turns.context`.
  - `TranscriptStore.pending_turns(self, session_id: str) -> list[tuple[int, Turn]]`: turns with rowid above `summary_through`, oldest first.
  - `TranscriptStore.save_summary(self, session_id: str, summary: str, through: int) -> None`
- Produces, in `compaction.py`:
  - `TURN_INPUT_CHARS = 2_000`, `SUMMARY_LIMIT_CHARS = 2_000`
  - `split_point(turns: list[tuple[int, Turn]], budget: int) -> int | None`: the rowid to summarize through, or `None`. It keeps at most `budget // 2`.
  - `async def compact_if_needed(store: TranscriptStore, session_id: str) -> bool`: True when it saved a summary. It never raises. It uses `default_limits().history_chars` as the budget.

Fixed copy:
- Summary system prompt: `"You summarize the earlier part of a conversation between the Pilot and BT, their assistant. Keep facts, decisions, open requests, and anything the Pilot asked BT to remember or do. If a previous summary is given, update it: keep what still holds, add the new turns, and drop what was settled. Reply with at most twelve short lines of plain prose."`
- Summary user message: `"Previous summary: {prior or 'none'}\n\nTurns to add:\n"` and one line per turn, `"Pilot: {text}"` or `"BT: {text}"`, each text cut to `TURN_INPUT_CHARS`.
- Fallback when the summary call fails or returns empty: `"{prior} " if prior else ""` + `"Some earlier turns were dropped to save space and could not be summarized."`
- Log lines: `log.info("compacted session=%s turns=%d kept_chars=%d summarized=%s", ...)` and `log.warning("compaction failed session=%s error_type=%s", ...)`.

- [ ] **Step 1: Write the failing tests**

`test_compaction.py`, with `_turns(sizes)` building alternating user/bt `(rowid, Turn)` pairs from rowid 1, starting on user. Budget 16,000 unless stated:
- `test_under_budget_is_left_alone`: four 1000-character turns give `None`.
- `test_split_keeps_a_tail_that_starts_on_a_user_turn`: twenty 1000-character turns. The turns after the returned rowid aren't empty, start with a user turn, and total at most 8,000.
- `test_oversized_latest_turn_is_kept_whole`: user 500, bt 500, user 20,000. `split_point` returns 2.
- `test_cloud_budget_follows_the_provider`: twenty 1000-character turns in a session. `compact_if_needed` returns False in `openai` mode and True in `ollama` mode.
- `test_compaction_saves_summary_and_history_starts_with_it`: `ollama` mode, a `TranscriptStore(':memory:')` session with twenty 1000-character turns, and `compaction.one_shot` returning `'Pilot parked on level 2.'`. `compact_if_needed` returns True. `as_chat_messages(sid)[0] == {'role': 'user', 'content': SUMMARY_PREFIX + 'Pilot parked on level 2.'}`, `[1]` is the first kept user turn, and total content is at most 16,000.
- `test_second_compaction_updates_the_prior_summary`: compact, add twenty more turns, compact again. The second `one_shot` user message starts with `'Previous summary: Pilot parked on level 2.'`.
- `test_failed_summary_still_bounds_history`: `one_shot` raises `openai.APIConnectionError`. It returns True, and the stored summary ends with `'could not be summarized.'`.
- `test_history_prefix_is_stable_between_compactions`: after a compaction, `m1 = as_chat_messages(sid)`. Add a 100-character user turn and a bt turn. `as_chat_messages(sid)[:len(m1)] == m1`.

`test_context_budget.py`:
- `test_fit_keeps_summary_and_current_turn`: system, a summary message, 100,000 characters of older turns, then the current user turn and one tool round. `fit_to_limits(..., LOCAL_LIMITS)` keeps the system message, the summary at index 1 and the whole current turn. The older turns it keeps start on a user turn, and the history it keeps totals at most `LOCAL_LIMITS.history_chars`.

`test_router.py`:
- `test_explicit_local_fits_history`: `openai` mode, 100,000 characters of history and `provider="local"`. The local call's history is at most `LOCAL_LIMITS.history_chars`.

`test_store.py`:
- `test_existing_database_gains_summary_columns`: a pre-change schema DB built with raw `sqlite3` opens, and `pending_turns` returns its turns.
- `test_history_endpoint_still_returns_summarized_turns`: after `save_summary(sid, 's', through)`, `history(sid)` still returns every turn.

`test_chat_ws.py`:
- `test_turn_compacts_before_answering`: monkeypatch `chat_ws.compact_if_needed` with an async spy. It runs once with `(store, sid)`, before `respond`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_compaction.py tests/test_context_budget.py tests/test_store.py tests/test_router.py tests/test_chat_ws.py`
Expected: FAIL. `bt.transcript.compaction`, `fit_to_limits` and `pending_turns` don't exist.

- [ ] **Step 3: Implement**

- `split_point`:
  1. Return `None` when the total text length is at most `budget`.
  2. Walk back from the newest turn, adding turns while the kept total stays at most `budget // 2`. Always keep the newest turn, even when it alone is larger.
  3. Move the start forward to the first user turn at or after it. If there is none, start at the newest user turn.
  4. Return the rowid just before the start, or `None` when nothing comes before it.
- `as_chat_messages(session_id, limit=50)`: the last `limit` of `pending_turns`, mapped as now. When a summary is stored, put `{"role": "user", "content": SUMMARY_PREFIX + summary}` first. It stays its own message so `fit_to_limits` can keep it, and it isn't a second system message, which Pipecat's `system_instruction` handling doesn't expect. Two user messages in a row are fine for OpenAI and Ollama.
- `fit_to_limits`:
  1. Split the messages into the system message, an optional summary message (content starts with `SUMMARY_PREFIX`), older turns, and the current turn (from the latest user message on).
  2. Add older turns newest first while their total stays at most `limits.history_chars`, and move the start to a user turn.
  3. Run `clear_old_tool_output(result, limits.turn_tool_chars)`.
- Router: when the turn starts on the local tier, rebind `working = fit_to_limits(working, LOCAL_LIMITS)`.
- `compact_if_needed`:
  1. Read `pending_turns` and the summary through `asyncio.to_thread`.
  2. Call `split_point`, build the summary input, call `one_shot`, cut the reply to `SUMMARY_LIMIT_CHARS`, and `save_summary`.
  3. An exception from `one_shot`, or an empty reply, uses the fallback copy. Any other error logs and returns False.
  `one_shot` picks the model from `BT_LLM_PROVIDER` and already cuts the input for Qwen.
- `chat_ws.answer` and `gateway.chat`: `await compact_if_needed(store, sid)` after storing the user turn and before `as_chat_messages`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Manual check**

Run `make server` with `BT_LLM_PROVIDER=ollama` (so the budget is 16,000). In one text session, paste ten 2,000-character messages. `make logs` shows one `compacted` line, and the next reply still knows a fact from the first message.

- [ ] **Step 6: Commit**

```bash
git add server/bt/transcript server/bt/llm server/bt/gateway server/tests
git commit -m "feat: fold old turns into a rolling session summary"
```

---

### Task 12: Record cut-off turns

From Hermes saving messages after each turn, and the write-ahead rule from agent reliability work: record an effect before the turn can be lost. Today a turn that fails or is cancelled (the client disconnects) stores only the user turn. If `calendar_create_event` already ran, the next turn doesn't know, and a retry creates the event twice.

**Files:**
- Modify: `server/bt/gateway/chat_ws.py` (`run_turn`, `answer`)
- Test: `server/tests/test_chat_ws.py`

**Interfaces:**
- Produces, in `chat_ws.py`: `cut_off_note(used: list[str]) -> str`.
- `answer(self, message, telemetry, ctx)` takes the `ToolContext` that `run_turn` now builds, so `run_turn` can read `ctx.used` after a failure.

Fixed copy: `"(This reply was cut off. Tools that already ran: {names}.)"`, where `names` is `", ".join` of `used` with duplicates removed, first-seen order.

- [ ] **Step 1: Write the failing tests**

- `test_cut_off_turn_records_tools_that_ran`: the fake `respond` appends `'calendar_create_event'` twice and `'memory_search'` once to `kw['ctx'].used`, then raises `RuntimeError`. Roles are `['user', 'bt']`, and the bt text is `'(This reply was cut off. Tools that already ran: calendar_create_event, memory_search.)'`.
- `test_disconnect_after_a_tool_records_it`: like `test_disconnect_mid_turn_cancels_and_stores_no_reply`, but the fake appends `'memory_write'` to `kw['ctx'].used` before sleeping. Afterwards roles are `['user', 'bt']` and the lease is released.
- `test_failed_turn_reports_and_stores_no_reply` and `test_disconnect_mid_turn_cancels_and_stores_no_reply` stay as they are: no tools ran, so nothing is stored.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_chat_ws.py`
Expected: FAIL. Roles are `['user']`.

- [ ] **Step 3: Implement**

- `run_turn` builds `ctx = default_context(sid, "text") if CONFIG.tools_enabled else None` and passes it to `answer`.
- In both the `except Exception` and `except asyncio.CancelledError` branches, when `ctx and ctx.used`, call `store.add_turn(sid, "bt", cut_off_note(ctx.used))` directly, not through `asyncio.to_thread`. An await during cancellation can be cancelled again, and the insert is one quick statement.
- The note is in the transcript, so the Mac app shows the Pilot which tools ran.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/gateway/chat_ws.py server/tests/test_chat_ws.py
git commit -m "feat: record tools that ran before a turn was cut off"
```

---

### Task 13: Confirm destructive server tools in a later turn

From Lindy's approval step and Hermes' approval callback. The Mac app already asks before calendar writes. Server tools have no such step, and Task 8's "Ask the Pilot before deleting or merging" is only prompt text.

The first call to a tool marked `confirm=True` doesn't run. It records a proposal and tells the model to ask. The same call with the same arguments runs only in a later user turn, within 10 minutes. The model can't confirm itself in one turn, and the loop guard (Task 5) stops it trying more than twice.

**Files:**
- Create: `server/bt/tools/confirm.py`
- Modify: `server/bt/tools/registry.py` (`ToolSpec.confirm`, `tool(confirm=)`, `ToolContext.turn_id`, `ToolContext.new_turn`, `run_tool`)
- Modify: `server/bt/tools/memory_upkeep.py` (`confirm=True` on `memory_delete` and `memory_consolidate`)
- Modify: `server/bt/voice/pipeline.py` (`on_user_turn=ctx.new_turn`)
- Test: `server/tests/test_confirm.py` (new), `server/tests/test_voice_pipeline.py`

**Interfaces:**
- Consumes: `fingerprint` (Task 5), `tool_error` (Task 3), `memory_delete` and `memory_consolidate` (Task 8).
- Produces:
  - `ToolSpec.confirm: bool = False`, after `surfaces`. `tool(..., confirm: bool = False)`.
  - `ToolErrorCode.NEEDS_CONFIRMATION`.
  - `ToolContext.turn_id: str = field(default_factory=lambda: uuid4().hex)` and `ToolContext.new_turn(self) -> None`, which resets `guard` and sets a new `turn_id`. Task 5's pipeline line becomes `on_user_turn=ctx.new_turn if ctx else None`.
  - In `confirm.py`: `CONFIRM_TTL_SECS = 600`, `check(spec: ToolSpec, ctx: ToolContext, arguments: Mapping[str, Any]) -> str | None`, `reset_all() -> None` (tests).

Fixed copy: `"{name} changes stored data. Tell the Pilot exactly what it will do and ask them to confirm. If they agree, call it again with the same arguments."`

- [ ] **Step 1: Write the failing tests**

`test_confirm.py` (`confirm.reset_all()` in a fixture; a `wipe` spec with `confirm=True` and a handler that counts runs; `_ctx(session='s')` builds a fresh text context, which has a fresh `turn_id`):
- `test_first_call_asks_for_confirmation`: the result starts with `'Error NEEDS_CONFIRMATION: wipe changes stored data.'`, and the handler didn't run.
- `test_same_turn_cannot_confirm_itself`: two calls on one context both return `NEEDS_CONFIRMATION`.
- `test_later_turn_with_same_arguments_runs`: a call on context A, then the same arguments on context B (same session), runs the handler once.
- `test_different_arguments_need_their_own_confirmation`: `{'name': 'a'}` on A, then `{'name': 'b'}` on B returns `NEEDS_CONFIRMATION`.
- `test_proposal_expires`: move `confirm.time.monotonic` 601 seconds on between A and B. B returns `NEEDS_CONFIRMATION`.
- `test_proposal_is_used_once`: after B runs, the same arguments on C return `NEEDS_CONFIRMATION`.
- `test_other_sessions_cannot_confirm`: A in session `'s'`, B in session `'t'`. B returns `NEEDS_CONFIRMATION`.
- `test_unmarked_tools_skip_the_check`: a spec with `confirm=False` runs on the first call.

`test_voice_pipeline.py`:
- `test_new_turn_rotates_turn_id_and_resets_guard`: after `ctx.new_turn()`, `ctx.turn_id` differs and `ctx.guard.tripped` is False.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_confirm.py tests/test_voice_pipeline.py`
Expected: FAIL. `bt.tools.confirm` doesn't exist, and `ToolSpec` has no `confirm` field.

- [ ] **Step 3: Implement**

- `confirm.check` keeps `_PENDING: dict[tuple[str, str], tuple[float, str]]`, mapping `(session_id, fingerprint)` to `(monotonic time, turn_id)`, under a `threading.Lock`.
  - Fingerprint: `fingerprint(spec.name, json.dumps(arguments))`.
  - A pending entry from a different `turn_id`, younger than `CONFIRM_TTL_SECS`: pop it and return `None`.
  - Otherwise store or refresh the entry with the current turn, and return the copy through `tool_error(NEEDS_CONFIRMATION, ...)`.
  - Mark the dict `# ponytail: per-process dict, lost on restart (the Pilot is asked again); fine for one worker`.
- `run_tool` order: `authorize` (surface), the required-argument check, then `confirm.check` when `spec.confirm`, then the handler. Missing arguments never create a proposal.
- Mark `memory_delete` and `memory_consolidate` with `confirm=True`. Leave `memory_write` unmarked; replacing a memory by name is how the model corrects a fact.
- `pipeline.py`: `on_user_turn=ctx.new_turn if ctx else None`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tools server/bt/voice/pipeline.py server/tests
git commit -m "feat: confirm destructive server tools in a later turn"
```

---

### Task 14: Parallel tool calls

Luna and Terra can ask for several tools in one round, such as calendar and memory together. The router runs them one at a time today. Voice already runs them in parallel, because Pipecat's `run_in_parallel` defaults to True, so two voice `memory_write` calls can overlap today. That is a race on `MEMORY.md`.

The rule for both paths: read-only server tools and client tools run concurrently, and other server tools take a per-turn lock and run one at a time. Results go back in call order (Hermes). Qwen gets the same code; it just rarely asks for two.

**Files:**
- Modify: `server/bt/tools/registry.py` (`ToolSpec.readonly`, `tool(readonly=)`, `ToolContext.write_lock`, `bridge`)
- Modify: `server/bt/tools/builtin.py`, `server/bt/tools/memory_upkeep.py` (mark read-only tools)
- Modify: `server/bt/llm/router.py` (tool round), `server/bt/llm/streaming.py` (`completion_kwargs`)
- Test: `server/tests/test_router.py`, `server/tests/test_registry.py`, `server/tests/test_streaming.py`

**Interfaces:**
- Consumes: `LoopGuard.check` and `record` (Task 5), `clip_result` (Task 10).
- Produces:
  - `ToolSpec.readonly: bool = False`, after `confirm`. `tool(..., readonly: bool = False)`.
  - `ToolContext.write_lock: asyncio.Lock = field(default_factory=asyncio.Lock)`.
  - `completion_kwargs` adds `parallel_tool_calls=True` for `openai` when tools are sent. It is constant per tier, so it doesn't clear the cache. Ollama gets nothing new.
- Read-only: `environment_report`, `memory_search`, `memory_read`, `load_skill`, `session_search`, `memory_review`, and Task 15's `task_list`.

- [ ] **Step 1: Write the failing tests**

`test_router.py`:
- `test_readonly_calls_run_together`: one round with two calls to read-only tools whose fake handlers `await asyncio.sleep(0.2)`. The round takes under 0.35 seconds, and the tool messages follow call order.
- `test_write_calls_never_overlap`: one round with three `memory_write` calls. A counter in the fake handler records at most one running at a time.
- `test_client_and_server_results_keep_call_order`: client, server, client in one round. The tool messages appear in that order with matching `tool_call_id`s.
- `test_loop_guard_sees_parallel_calls_in_order`: one round with three identical calls. The first two run and the third gets `LOOP_DETECTED`.

`test_registry.py`:
- `test_voice_bridge_serializes_writes`: two `bridge` calls for a non-read-only tool started together on one context never overlap.

`test_streaming.py`: `completion_kwargs` for openai with tools has `parallel_tool_calls is True`. Without tools, or for Ollama, it has no such key.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_router.py tests/test_registry.py tests/test_streaming.py`
Expected: FAIL. The router runs calls one after another, and `ToolSpec` has no `readonly` field.

- [ ] **Step 3: Implement**

- Router tool round:
  1. Run `guard.check` for each call in call order. A blocked call gets its error content and doesn't run.
  2. Run the rest under one `asyncio.TaskGroup`, so a client failure cancels the siblings. A server tool that isn't read-only runs inside `async with write_lock`. Create `write_lock = asyncio.Lock()` per `respond` call, because tests pass `SimpleNamespace` contexts.
  3. `guard.record` and append the tool messages in call order.
  4. Count the round once against `tool_rounds`, however many calls it held.
- `bridge`: a non-read-only spec runs inside `async with ctx.write_lock`.
- Telemetry keeps per-call `tool_elapsed`. With overlap, `tool_execution_ms` can exceed the round's wall time; that is expected.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tools server/bt/llm server/tests
git commit -m "feat: run independent tool calls in parallel"
```

---

### Task 15: Background tasks: queue, tools and worker

A turn stops after 25 tool rounds on the cloud and 10 on Qwen, and it dies when the client disconnects. A background task outlives both. The Pilot says "look through my memories and draft a weekly plan" or "every morning at 8, summarize what's due". BT queues a task, answers right away, and posts the result to the conversation later.

The design takes from OpenClaw (a separate lane so background work never blocks a reply, one run at a time), Manus (a plan the model rewrites as it goes, kept at the end of its context), and Hermes (an iteration budget, then a summary of what got done).

A task runs in segments. Each segment is one `respond()` call with the tier's tool round budget. When a segment spends its budget, its last reply is saved as a note and the next segment starts from the goal, the plan and the notes. The plan and notes live in SQLite, so a restart loses at most the segment in flight. Task 16 handles restarts.

Background tasks can't use the Mac app's client tools (calendar), because the app may be closed. On Qwen a task usually finishes in one short segment, which is a worse answer, but still an answer.

**Files:**
- Create: `server/bt/tasks/__init__.py`, `server/bt/tasks/store.py`, `server/bt/tasks/runner.py`, `server/bt/tasks/tools.py`
- Modify: `server/bt/library.py` (`SURFACES` adds `"task"`)
- Modify: `server/bt/tools/registry.py` (`ToolContext.task_id`, `load_builtins` imports `bt.tasks.tools`)
- Modify: `server/bt/tools/confirm.py` (refuse on the task surface)
- Modify: `server/bt/llm/router.py` (`respond(surface=)`, `LLMResponse.budget_spent`)
- Modify: `server/bt/config.py` (`tasks_enabled`), `server/bt/gateway/gateway.py` (`lifespan` starts and stops the worker)
- Modify: `server/tests/conftest.py` (`BT_TASKS=0`)
- Test: `server/tests/test_task_store.py`, `server/tests/test_task_runner.py`, `server/tests/test_task_tools.py` (all new), `server/tests/test_confirm.py`

**Interfaces:**
- Consumes: `respond`, `ModelUnavailable` (Task 1); `authorize` and surfaces (Task 4); `confirm.check` (Task 13).
- Produces, in `store.py`:
  - Table `tasks(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, title TEXT NOT NULL, goal TEXT NOT NULL, status TEXT NOT NULL, plan TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', run_at REAL NOT NULL, every_secs REAL, segments INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0, result TEXT, error_code TEXT, silent INTEGER NOT NULL DEFAULT 0, delivered INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL, updated_at REAL NOT NULL)`, in the same file as `CONFIG.db_path`. Status is one of `queued`, `running`, `done`, `failed`, `cancelled`. Task 16 uses `every_secs`, `attempts` and `delivered`, and Task 17 uses `silent`.
  - `@dataclass(frozen=True) class Task` with those fields.
  - `class TaskStore(db_path: str)`, with its own connection and lock (WAL is already on), and `get_task_store()`.
  - Methods: `create(session_id, title, goal, *, run_at, every_secs=None, silent=False) -> Task`, `get(task_id) -> Task | None`, `find(session_id, prefix) -> Task | None`, `list_for(session_id, limit=10) -> list[Task]`, `active_count() -> int`, `next_due(now) -> Task | None`, `mark_running(task_id)`, `save_plan(task_id, plan)`, `add_note(task_id, note)`, `requeue(task_id, *, run_at, error_code=None)`, `finish(task_id, status, result) -> Task`, `cancel(task_id) -> bool`.
  - Constants: `MAX_ACTIVE_TASKS = 20`, `PLAN_CHARS = 4_000`, `NOTES_CHARS = 8_000` (keep the newest).
- Produces, in `runner.py`:
  - `MAX_SEGMENTS = 8`, `POLL_SECS = 30`
  - `class TaskRunner` with `start() -> None`, `async stop() -> None`, `wake() -> None`, `cancel(task_id: str) -> bool`, and `async run_segment(task: Task) -> None`. Plus `get_runner() -> TaskRunner`.
  - `segment_prompt(task: Task) -> str`
- Produces, in `router.py`: `respond(..., surface: str = "text")` passes `surface` to `render_system_prompt`. `LLMResponse.budget_spent: bool = False` is True when the reply came from the forced `tool_choice="none"` call.
- Produces: `ToolContext.task_id: str | None = None`. `CONFIG.tasks_enabled` from `BT_TASKS`, default on.
- Tools in `bt/tasks/tools.py`:
  - `task_start(title, goal, start_in_minutes?: integer)`: text and voice. Title at most 80 characters, goal at most 4,000, `start_in_minutes` from 0 to 10,080 (7 days). Over `MAX_ACTIVE_TASKS` raises `ValueError`, which becomes `REJECTED`. It calls `get_runner().wake()`. Manifest: `"You can start a background task with task_start when a request needs many steps or should happen later. Its result is posted in this conversation."`
  - `task_list()`: text and voice, read-only. It lists the session's tasks: short id, title, status, and when it runs next.
  - `task_cancel(task)`: text and voice. Takes a short id prefix and calls `get_runner().cancel`.
  - `task_plan(plan)`: task surface only. It saves the plan cut to `PLAN_CHARS` and returns `"Plan saved.\n{plan}"`. That puts the plan at the end of the context again (Manus' recitation).

Fixed copy:
- `segment_prompt`: `"Background task: {title}\nGoal: {goal}\n"` + (`"Plan so far:\n{plan}\n"` if plan) + (`"Notes from earlier steps:\n{notes}\n"` if notes) + `"You are working on your own; the Pilot is not watching and can't answer questions. Write or update your plan with task_plan first, then work through it. When the goal is met, reply with the result for the Pilot. If you can't finish, say what is left."`
- `task_start` replies: `"Started {title} ({short_id}). I'll post the result here."` and, when delayed, `"Scheduled {title} ({short_id}) for {HH:MM on Weekday}."`
- Confirm refusal on the task surface: `"{name} needs the Pilot's confirmation, which a background task can't get. Note it in your result so the Pilot can do it in conversation."`
- Log lines: `log.info("task_segment id=%s status=%s segment=%d tools=%d", ...)` and `log.warning("task_failed id=%s error_code=%s attempts=%d", ...)`.

- [ ] **Step 1: Write the failing tests**

`test_task_store.py` (`TaskStore(':memory:')`):
- `test_create_and_next_due_respects_run_at`: a task due in an hour isn't returned by `next_due(now)` and is by `next_due(now + 3601)`.
- `test_notes_keep_the_newest`: adding 10,000 characters of notes keeps the last `NOTES_CHARS`.
- `test_cancel_only_active`: `cancel` on a queued task returns True, and on a done task returns False.

`test_task_tools.py`:
- `test_task_start_queues_and_wakes`: on a text context, `task_start` stores a queued task for `ctx.session_id`, calls the runner's `wake` spy, and replies with the copy.
- `test_task_start_rejects_the_21st_active_task`: `Error REJECTED`.
- `test_task_plan_is_task_only`: on a text context, `Error SURFACE_NOT_ALLOWED`. On a task context with `task_id`, the plan is saved and echoed.
- `test_task_cancel_by_prefix`.

`test_task_runner.py` (`router.respond` monkeypatched; a fake transcript store for Task 16 later):
- `test_finished_segment_marks_done`: the fake `respond` returns `LLMResponse('Plan drafted.', 'openai')`. The task is `done` with `result == 'Plan drafted.'`. `respond` got `surface='task'`, and its one user message is `segment_prompt(task)`.
- `test_spent_budget_continues_with_a_note`: the first `respond` returns `budget_spent=True` with text `'Did steps 1-3.'`, and the second returns a plain result. The second segment's prompt contains `'Notes from earlier steps:\nDid steps 1-3.'`, and the task is done after two segments.
- `test_segments_are_capped`: `respond` always returns `budget_spent=True`. After `MAX_SEGMENTS` the task is `done`, and its result is the last reply.
- `test_model_unavailable_requeues_with_backoff`: `respond` raises `ModelUnavailable`. The task is queued again with `run_at` 60 seconds later and `attempts == 1`.
- `test_cancel_stops_a_running_segment`: `respond` sleeps. `runner.cancel(id)` while it runs leaves the task `cancelled`, and no result is written.

`test_confirm.py`:
- `test_task_surface_never_confirms`: a `confirm=True` tool called on two task contexts with different `turn_id`s returns the task refusal both times.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_task_store.py tests/test_task_tools.py tests/test_task_runner.py tests/test_confirm.py`
Expected: FAIL. `bt.tasks` doesn't exist.

- [ ] **Step 3: Implement**

- `TaskRunner` loop:
  1. `next_due(time.time())`. Run its segment, then look again straight away.
  2. With nothing due, wait on an `asyncio.Event` for at most `POLL_SECS`. `wake()` sets the event.
  3. Run one segment at a time. Mark this `# ponytail: one segment at a time; a second lane if tasks queue up behind each other`.
- `run_segment`:
  1. `mark_running`.
  2. Build `ctx = default_context(task.session_id, "task")` with `task_id` set.
  3. Call `respond([{"role": "user", "content": segment_prompt(task)}], task.goal, ctx=ctx, surface="task")`. No `session_id`, so the turn note carries no conversation facts.
  4. With `budget_spent` and fewer than `MAX_SEGMENTS` segments: `add_note` the reply plus `"Tools run: ..."` from `ctx.used`, and requeue with `run_at=now`.
  5. Otherwise `finish(task.id, "done", reply)`.
  6. `ModelUnavailable` or another exception: `attempts + 1`. Below 3 attempts, requeue at now + `(60, 300, 900)[attempts - 1]` with the error type as `error_code`. At 3, `finish(..., "failed", ...)`.
  7. Before writing any of this, re-read the status and leave a `cancelled` task alone.
- `cancel(task_id)` marks the row cancelled and cancels the running `asyncio.Task` if it holds that id.
- `confirm.check`: when `ctx.surface == "task"`, always return the task refusal through `tool_error(NEEDS_CONFIRMATION, ...)`. A later segment has a new `turn_id`, so without this a task could confirm its own proposal.
- `gateway.lifespan`: when `CONFIG.tasks_enabled`, `get_runner().start()` after startup checks, and `await get_runner().stop()` before `store.close()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tasks server/bt/library.py server/bt/tools server/bt/llm/router.py server/bt/config.py server/bt/gateway/gateway.py server/tests
git commit -m "feat: run background tasks in segments with a saved plan"
```

---

### Task 16: Background tasks: delivery, schedules and restarts

Task 15 writes results to the `tasks` table. This task gets them to the Pilot, repeats scheduled tasks, and recovers after a restart.

**Files:**
- Modify: `server/bt/tasks/store.py` (`undelivered`, `mark_delivered`, `recover_running`)
- Modify: `server/bt/tasks/runner.py` (delivery, schedules, recovery on `start`)
- Modify: `server/bt/tasks/tools.py` (`task_start(every_minutes?)`)
- Modify: `server/bt/gateway/gateway.py` (`GET /tasks`)
- Test: `server/tests/test_task_runner.py`, `server/tests/test_task_tools.py`, `server/tests/test_gateway.py`

**Interfaces:**
- Consumes: `TaskStore`, `TaskRunner` (Task 15); `TranscriptStore.conversation` and `add_turn`.
- Produces:
  - `TaskStore.undelivered() -> list[Task]`, `mark_delivered(task_id)`, and `recover_running() -> list[Task]`, which returns the tasks it requeued or failed.
  - `finish` sets `delivered = 0` unless the task is `silent`.
  - `task_start(..., every_minutes?: integer)`, at least `MIN_EVERY_MINUTES = 15`.
  - `GET /tasks?session_id=` returns `[{id, title, status, run_at, every_secs, updated_at}]`. It never returns goals, plans, notes or results; those reach the Pilot through the transcript.
  - `MAX_ATTEMPTS = 3`

Fixed copy:
- Done: `"Background task finished: {title}. {result}"`
- Failed: `"Background task stopped: {title}. {result}"`
- Restart note added to a requeued task: `"An earlier attempt was interrupted by a restart. Check before repeating any change."`
- Gave up after restarts: `"BT restarted during this task three times, so it stopped."`
- Failed after model errors: `"BT couldn't reach a model after three tries."`

- [ ] **Step 1: Write the failing tests**

`test_task_runner.py`:
- `test_result_is_posted_to_the_conversation`: after a done segment, the transcript has a bt turn `'Background task finished: Weekly plan. Plan drafted.'`, and the task is delivered.
- `test_busy_conversation_delays_delivery`: while `store.conversation(sid)` is held, delivery leaves `delivered == 0`. After release, the next loop posts it once.
- `test_deleted_session_drops_delivery`: `conversation` raises `KeyError`. The task is marked delivered and nothing raises.
- `test_silent_task_posts_nothing`.
- `test_repeating_task_is_rescheduled`: a done task with `every_secs=3600` is `queued` again with `run_at` about an hour later, `segments == 0`, its notes cleared and its plan kept. Its result was delivered.
- `test_restart_requeues_running_tasks`: a `running` row with `attempts=0` is `queued` after `recover_running()`, with `attempts == 1` and the restart note in its notes.
- `test_third_restart_fails_and_tells_the_pilot`: a `running` row with `attempts=2` becomes `failed` with the gave-up copy, and delivery posts `'Background task stopped: ...'`.

`test_task_tools.py`:
- `test_every_minutes_has_a_floor`: `every_minutes=5` returns `Error REJECTED`.

`test_gateway.py`:
- `test_tasks_endpoint_lists_without_content`: the response has the listed keys only.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_task_runner.py tests/test_task_tools.py tests/test_gateway.py`
Expected: FAIL. Nothing is delivered and there is no `/tasks` route.

- [ ] **Step 3: Implement**

- The runner loop calls `deliver_pending()` before looking for due work. For each undelivered task, `with transcript.conversation(sid):` add the bt turn with `compute=None`, then `mark_delivered`. The lease keeps a result from landing in the middle of a live turn. `RuntimeError` (busy) leaves it for the next loop, and `KeyError` marks it delivered and logs.
- After a delivered `done` with `every_secs`, requeue with `run_at = now + every_secs`, `segments = 0`, empty notes and the plan kept.
- `start()` runs `recover_running()` once before the loop. Below `MAX_ATTEMPTS`, it requeues with the restart note. At `MAX_ATTEMPTS`, it finishes as failed with the gave-up copy.
- Task 15's model-error failure uses the failed-after-model-errors copy as its result.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Manual check**

With a key, run `make server` and ask BT in text chat: "In one minute, list my memories and suggest two to merge." BT answers right away. A minute later, the conversation shows "Background task finished: ...". Ask for another, stop the server while it runs, and start it again: the task finishes after restart.

- [ ] **Step 6: Commit**

```bash
git add server/bt/tasks server/bt/gateway/gateway.py server/tests
git commit -m "feat: deliver, repeat and recover background tasks"
```

---

### Task 17: Background memory review

From Hermes' periodic review: every 10 user turns it asks whether anything should be saved. BT runs it as a silent background task, so it never slows a reply. Luna only: an 8B model writing memories unsupervised would fill them with noise, so in `ollama` mode the review is skipped.

**Files:**
- Create: `server/bt/tasks/memory_review.py`
- Modify: `server/bt/gateway/chat_ws.py` (`answer`), `server/bt/gateway/gateway.py` (`chat`)
- Test: `server/tests/test_memory_review_task.py` (new)

**Interfaces:**
- Consumes: `TaskStore.create(..., silent=True)`, `get_runner().wake()` (Tasks 15 and 16); `openai_default` (Task 1).
- Produces: `REVIEW_EVERY = 10`, `REVIEW_TURNS_CHARS = 20_000`, `maybe_queue_review(store: TranscriptStore, session_id: str) -> bool`.

Fixed copy: the goal is `"Read these recent turns and save any lasting fact about the Pilot with memory_write. Search first and skip what is already stored. Reply with the names you saved, or: Nothing to save.\n\n"` plus the newest turns as `"Pilot: ..."` and `"BT: ..."` lines, cut to `REVIEW_TURNS_CHARS`. The title is `"Memory review"`.

- [ ] **Step 1: Write the failing tests**

- `test_review_queues_every_tenth_user_turn`: on the 10th and 20th user turns of a session, a silent task titled `'Memory review'` is created. On the 9th and 11th, none is.
- `test_review_skipped_in_ollama_mode`: `llm_provider='ollama'` creates nothing, even with a key.
- `test_review_skipped_with_tasks_off`: `tasks_enabled=False` creates nothing.
- `test_review_goal_holds_recent_turns_only`: the goal ends with the newest turns and is at most `REVIEW_TURNS_CHARS` past the fixed text.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_memory_review_task.py`
Expected: FAIL. `bt.tasks.memory_review` doesn't exist.

- [ ] **Step 3: Implement**

- `maybe_queue_review` counts the session's user turns. It queues only when the count is a multiple of `REVIEW_EVERY`, `openai_default()` holds and `CONFIG.tasks_enabled` is on.
- `chat_ws.answer` and `gateway.chat` call it after storing the bt reply, through `asyncio.to_thread`. It never raises into the turn: log `memory_review_skipped error_type=%s` and carry on.
- The review runs on the task surface, so `memory_delete` and `memory_consolidate` are refused there (Task 15). It can only add and correct memories.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && uv run python -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/bt/tasks/memory_review.py server/bt/gateway server/tests
git commit -m "feat: review recent turns for memories in the background"
```

---

## Not in this plan

- **The Responses API** (hosted web search, MCP servers, file search, server-side compaction, `previous_response_id`). Ollama only speaks Chat Completions, so moving would split the router into two request shapes, and OpenAI's compaction output is encrypted, so Qwen couldn't read it after a switch to `ollama` mode. Revisit if web search becomes a must-have; a server-side `web_search` tool that calls the Responses API on its own would keep the router as it is.
- **`gpt-realtime-2.1` for voice.** Terra and Luna don't support the Realtime API. Speech-to-speech would replace Whisper, Piper and the Pipecat routing, and costs about $32/$64 per million audio tokens. Task 2 keeps the current pipeline.
- **Strict function schemas.** OpenAI's strict mode needs every property listed as required, and BT's tools have optional arguments. Task 3's error codes show how often bad arguments actually happen; measure first.
- **Explicit cache breakpoints and 12-hour cache retention.** The 30-minute default and the stable prefix (Task 11) cover a conversation. Watch `cached_tokens` (Task 1) before paying 2.5× for 12-hour writes.
- **Screenshots as context.** Luna and Terra accept images, but the Mac app sends text context only.
- **Mac UI for background tasks** (a list, notifications, cancel buttons). Task 16's `/tasks` endpoint and the transcript entries are enough to start.
- **Client tools in background tasks.** Calendar tools run in the Mac app, which may be closed when a task runs.
- **Hermes' self-written skills.** Revisit once Task 17's memory review has run for a while and its saved memories look useful.
- **OpenClaw's queue modes (steer, followup, collect).** The Mac app disables Send while a reply streams, and a voice and text overlap already gets a clear busy error.
- **Recording voice token usage for the context watch.** It needs Pipecat's usage metrics frames in `TranscriptObserver`.
- **Cindy's longer-window loop rules** (16-call rotation, 128-call read window). A turn now runs up to 25 rounds, so the 16-call rule could fire in principle. Add it if `LOOP_DETECTED` counts (Task 3) show rotations that the repeat and ping-pong rules miss.
- **Showing `tool_errors`, `context_ratio` and `cached_tokens` in the Dev UI or the Mac Diagnostics window.** All three are already in the metrics snapshot.
- **The `digest` memory type.** Task 11's session summary holds what dropped out of context.
