# Agent Pipeline Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Borrow six patterns from Cindy (github.com/makecindy/cindy) for BT's tool and memory pipeline: tool error codes with counts, a fixed tool list with call-time checks, a loop guard, FTS5 search over memories and past sessions, memory upkeep tools, and a warning before the context window fills.

**Architecture:** All tool calls already pass through `run_tool` in `bt/tools/registry.py`. Error formatting and surface checks go there. The loop guard sits one level up: in the router's tool loop for text, and in the Pipecat bridge for voice. Search moves to SQLite FTS5: an in-memory index over the memory files, and an FTS5 table kept in step with `turns` by triggers. A small `context_watch` module records prompt-token pressure per session and adds one line to `turn_note` when it gets high.

**Tech Stack:** Python 3.14, FastAPI, Pipecat, OpenAI SDK against Ollama, stdlib `sqlite3` (FTS5 is present: SQLite 3.54.1 was checked with `tokenize="porter unicode61"`), pytest.

**Source:** the Cindy review in this conversation (2026-10-25), with Cindy's references `packages/maker-core/src/agents/shared/loop-guard.ts`, `packages/lizi-mcps/src/tool-error-telemetry.ts`, `packages/lizi-mcps/src/tool-call-authority.ts`, `packages/lizi-mcps/src/memory/*`, `packages/maker-core/src/memory/flush-controller.ts`.

## Global Constraints

- Run Python from `server/`: `uv run python -m pytest -q` (plain `uv run pytest` breaks on hidden `.pth` files; see AGENTS.md).
- No new dependencies.
- Keep the system prompt stable. Per-turn facts go through `turn_note`. Never vary the tool list between turns.
- Diagnostics and log lines added here carry tool names, codes, counts and ratios only. Never message text or tool arguments.
- Tools return prose strings. Errors are prose too, starting `Error <CODE>: `.
- Tabs for indentation, matching the existing server code.
- Commit messages: `<type>: <description>`, no attribution lines (user rule).

## Review Focus

1. A voice session spans many turns on one `ToolContext`. Asking the same thing twice in two turns must not trip the loop guard. Pinned in Task 3 (observer resets the guard on each user turn).
2. Search text made of FTS5 syntax (`"NEAR(* -`) or only filler words must return no results, never raise. Pinned in Task 4.
3. An existing `bt.sqlite3` with turns but no FTS table must have those turns searchable after upgrade. Pinned in Task 5.
4. `memory_consolidate` listing its own target as a source must keep the target. An unknown source must change nothing. Pinned in Task 6.
5. With `BT_CONTEXT_LIMIT` unset, the context watch is fully off: no usage requests added, no log, no nudge. Pinned in Task 7.

---

### Task 1: Tool error codes, schema on bad arguments, error counts

**Files:**
- Modify: `server/bt/tools/registry.py` (`run_tool`, `dispatch_call`)
- Modify: `server/bt/llm/router.py` (tool loop, around line 200)
- Modify: `server/bt/llm/telemetry.py` (`TurnMetrics`)
- Modify: `server/bt/gateway/chat_ws.py` (`call_client` return strings)
- Test: `server/tests/test_registry.py`, `server/tests/test_router.py`, `server/tests/test_telemetry.py`, `server/tests/test_chat_ws.py`

**Interfaces:**
- Produces, in `registry.py`:
  - `class ToolErrorCode(StrEnum)` with `UNKNOWN_TOOL, INVALID_JSON, INVALID_ARGS, MISSING_ARGS, TIMEOUT, REJECTED, FAILED, BAD_RESULT, CLIENT_FAILED`. Tasks 2 and 3 add `SURFACE_NOT_ALLOWED` and `LOOP_DETECTED`.
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

### Task 2: Fixed tool list with a call-time surface check

The tool list is already fixed per connection. `chat_ws` rejects a second `hello`, and voice builds `pipecat_tools()` once. This task pins that with a test and adds the call-time check Task 6 needs: some tools are declared on every surface but refused on voice, so the list never varies.

**Files:**
- Modify: `server/bt/tools/registry.py` (`ToolSpec`, `tool`, `run_tool`, `manifest_lines`)
- Modify: `AGENTS.md` (Learned mistakes/behaviors)
- Test: `server/tests/test_registry.py`

**Interfaces:**
- Consumes: `tool_error`, `ToolErrorCode` (Task 1).
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

### Task 3: Loop guard

**Files:**
- Create: `server/bt/tools/loop_guard.py`
- Modify: `server/bt/tools/registry.py` (`ToolContext.guard`, Pipecat `bridge` in `_function_schema`)
- Modify: `server/bt/llm/router.py` (`MAX_TOOL_ITERATIONS`, tool loop)
- Modify: `server/bt/voice/persist.py` (`TranscriptObserver`), `server/bt/voice/pipeline.py` (`build_worker`)
- Test: `server/tests/test_loop_guard.py` (new), `server/tests/test_router.py`, `server/tests/test_voice_pipeline.py`

**Interfaces:**
- Consumes: `tool_error` (Task 1). Adds `ToolErrorCode.LOOP_DETECTED`.
- Produces, in `loop_guard.py`:
  - `@dataclass class LoopGuard` with:
    - `check(self, name: str, arguments: str | None) -> str | None` returns a block reason or `None`
    - `record(self, name: str, arguments: str | None, result: str) -> None`
    - `reset(self) -> None`
    - `tripped: bool`
  - Constants: `REPEAT_LIMIT = 2`, `WINDOW_SIZE = 6`, `WINDOW_DISTINCT_LIMIT = 2`.
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
- `test_tool_budget_final_call_forbids_more_tools`: change it to give each round a distinct `arguments` (`'{"query": "%d"}' % n`) so it still tests the budget. Assert `len(seen) == router.MAX_TOOL_ITERATIONS + 1`.
- `test_repeated_client_tool_is_blocked`: same as the first, through `call_client`. The client function runs 2 times.

`test_voice_pipeline.py`:
- `test_user_turn_resets_loop_guard`: build `TranscriptObserver(store, sid, {}, on_user_turn=spy)`, push a `TranscriptionFrame` from an `STTService` source, and assert the spy was called once.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && uv run python -m pytest -q tests/test_loop_guard.py tests/test_router.py tests/test_voice_pipeline.py`
Expected: FAIL. `bt.tools.loop_guard` is missing, and the observer doesn't accept `on_user_turn`.

- [ ] **Step 3: Implement**

- `router.py`:
  - Set `MAX_TOOL_ITERATIONS = 10` and delete the `# WARN` comment above it.
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

### Task 4: FTS5 memory search

**Files:**
- Modify: `server/bt/library.py` (`MemoryStore.search`, `_all` cache; remove `_score` and `_WEIGHTS`)
- Test: `server/tests/test_library.py`

**Interfaces:**
- Produces:
  - `fts_query(text: str) -> str | None` in `library.py`: the existing word filter (`_WORDS`, length > 2, not in `_FILLER`), each word wrapped in double quotes and joined with ` OR `. Returns `None` when no words are left. Task 5 reuses it.
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

### Task 5: Past-session search

**Files:**
- Modify: `server/bt/transcript/store.py` (schema, `__init__`, new `search_turns`)
- Modify: `server/bt/tools/registry.py` (`ToolContext.transcript`, `default_context`)
- Modify: `server/bt/tools/builtin.py` (new `session_search` tool)
- Test: `server/tests/test_store.py`, `server/tests/test_builtin_tools.py`

**Interfaces:**
- Consumes: `fts_query` (Task 4).
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

### Task 6: Memory upkeep tools

**Files:**
- Modify: `server/bt/library.py` (`MemoryStore.write` hard limit, new `size_warnings`, `delete`, `consolidate`)
- Create: `server/bt/tools/memory_upkeep.py` (`memory_delete`, `memory_consolidate`, `memory_review`)
- Modify: `server/bt/tools/registry.py` (`load_builtins` also imports `memory_upkeep`)
- Modify: `server/bt/tools/builtin.py` (`memory_write` appends warnings)
- Modify: `server/bt/llm/router.py` (new `one_shot`)
- Test: `server/tests/test_library.py`, `server/tests/test_memory_upkeep.py` (new)

**Interfaces:**
- Consumes: `surfaces=` and `SURFACE_NOT_ALLOWED` (Task 2).
- Produces, in `library.py`:
  - Constants `BODY_SOFT_CHARS = 1500`, `BODY_HARD_CHARS = 6000`. The index soft limit reuses `INDEX_LIMIT = 60`.
  - `MemoryStore.size_warnings(self, memory: Memory) -> list[str]`
  - `MemoryStore.delete(self, name: str) -> bool`
  - `MemoryStore.consolidate(self, sources: list[str], name: str, description: str, body: str, type: str = "user") -> Memory`
- Produces, in `router.py`: `async def one_shot(system: str, user: str) -> str`. It calls the local Ollama provider with no tools and returns `strip_thinking` text.
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

### Task 7: Warning before the context window fills

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

## Not in this plan

- **The `digest` memory type** (summaries of dropped context). BT doesn't compact context yet, so there's nothing to write into it.
- **Recording voice token usage for the context watch.** It needs Pipecat's usage metrics frames in `TranscriptObserver`. Add it if long voice sessions show truncation.
- **Cindy's longer-window loop rules** (16-call rotation, 128-call read window). BT caps a turn at 10 rounds, so they can't fire.
- **Showing `tool_errors` and `context_ratio` in the Dev UI or the Mac Diagnostics window.** Both are already in the metrics snapshot.
