# OpenAI Default Provider Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task-by-task. Check off each step after verification.

**Goal:** Use OpenAI by default for text and voice while retaining Ollama behind `BT_LLM_PROVIDER=ollama`.

**Architecture:** Add one startup setting and reuse the existing text and Pipecat provider implementations. Switching requires a server restart. Keep tools, transcripts, streaming, and client protocols unchanged.

**Tech stack:** Existing Python/FastAPI, OpenAI SDK, Pipecat, and pytest dependencies.

**Spec:** The user request in this thread: OpenAI as the default, Ollama retained, smallest complete implementation.

## Constraints and behavior

1. `BT_LLM_PROVIDER` accepts exactly `openai` or `ollama`; its default is `openai`. Invalid values fail startup with the setting name in the error.
2. OpenAI mode requires a nonblank `OPENAI_API_KEY`. Missing credentials fail startup; OpenAI request failures do not silently switch to Ollama.
3. Ollama mode preserves current local-first routing and OpenAI escalation. It can start without an OpenAI key, but escalation still requires one. This is not a local-only privacy mode.
4. Keep `BT_OPENAI_MODEL`, `BT_OLLAMA_MODEL`, and `BT_OLLAMA_URL`. Do not change model defaults, API families, context limits, tool execution, or speech recognition/synthesis.
5. No new dependencies, provider framework, runtime settings endpoint, Mac selector, database migration, commits, or deployment in this task. Preserve unrelated dirty files.

## Review focus

Check OpenAI mode with Ollama offline, startup without credentials, direct-cloud streaming/tool calls, explicit text overrides, and voice failure after partial output. The tasks below cover these cases.

## 1. Add the default and route text

**Files:** `server/bt/config.py`, `server/bt/gateway/gateway.py`, `server/bt/llm/router.py`, `server/.env.example`; tests in `server/tests/conftest.py`, `server/tests/test_config.py`, `server/tests/test_router.py`, and `server/tests/test_gateway.py`.

**Interface:** `Config.llm_provider: str`, defaulting from `BT_LLM_PROVIDER` to `openai`; `Config.validate_llm() -> None`, called during gateway lifespan before loading voice services.

- [ ] Set `BT_LLM_PROVIDER=ollama` in the existing test bootstrap before BT imports. Add explicit OpenAI-mode tests, and remove this environment variable in the test proving the production default. Keep tests independent of developer credentials.
- [ ] Write failing tests for the default, both valid values, invalid values, missing/blank OpenAI credentials, and gateway startup validation. Run those tests to confirm the intended failures.
- [ ] Implement the config field and validation. Set `BT_LLM_PROVIDER=openai` in `.env.example` and label credentials as required for OpenAI mode.
- [ ] Test and change initial text selection: explicit `provider="cloud"` or an escalation phrase selects OpenAI; otherwise explicit `provider="local"` selects Ollama; otherwise use `CONFIG.llm_provider`. Preserve the existing accepted override values and invalid-override error.
- [ ] Verify OpenAI starts without contacting Ollama, streams deltas, dispatches server/client tools, records `compute="openai"`, and propagates provider errors without local retries. Retain local fallback tests. Treat starting on OpenAI as already escalated so local-response heuristics never retry it. Keep clearer missing-key errors without exposing credentials.

## 2. Apply the same default to voice

**Files:** `server/bt/voice/routing.py`; tests in `server/tests/test_voice_routing.py` and `server/tests/test_voice_prompt.py`.

**Interface:** Keep `RoutedLLMService` and its existing methods; consume `CONFIG.llm_provider` without adding another service abstraction.

- [ ] Write failing tests for ordinary speech starting on OpenAI, no Ollama completion call in OpenAI mode, cloud error propagation, and correct `compute` attribution.
- [ ] Select the existing cloud service when the default is OpenAI or the user requests escalation. Otherwise retain the existing local-to-cloud sequence.
- [ ] Preserve provider-specific prompts: `/no_think` remains local-only. Keep turn notes, tools, stream closure, and cleanup unchanged.
- [ ] Verify both modes, cloud tool-only responses, and no retry/repeated speech after partial output. Keep existing timeout and prompt tests green.

## 3. Make readiness and status truthful

**Files:** `server/bt/gateway/gateway.py`, `server/bt/devui/routes.py`, `server/bt/devui/static/app.js`, `server/bt/client/app.mjs`, `server/bt/personality/system_prompt.py`; tests in `server/tests/test_gateway.py` and `server/tests/test_system_prompt.py`.

**Interface:** `/config` keeps its existing `model` field, now identifying the selected model, and adds `provider`. `/dev/config` adds selected `provider` and `model` while preserving existing fields. Never return credentials.

- [ ] Write failing tests showing OpenAI readiness does not contact Ollama, local readiness still checks the installed model, and config responses identify the selected provider/model without secrets. Add a focused dev-config response test to `test_gateway.py` using the existing router function if no dedicated test exists.
- [ ] Keep the database readiness check. In OpenAI mode validate provider configuration rather than requiring Ollama; in Ollama mode retain `/api/tags`. Do not send paid completions on health probes. Document that OpenAI readiness verifies configuration/storage, not remote authentication or model access.
- [ ] Update the developer model display to consume `model`. Replace the browser's unconditional “cloud fallback” wording with neutral provider wording; it cannot distinguish direct-cloud replies from fallback using the current response shape.
- [ ] Make the static prompt identify the configured primary provider/model without implying every turn used it. Keep per-turn facts in turn notes, actual-provider attribution in `compute`, and the explicitly local `environment_report` unchanged.

## 4. Document switching and verify

**Files:** `README.md`, plus the source/tests listed above. Apply Humanizer to edited prose.

- [ ] Update setup prerequisites, configuration table, routing paragraph, and pipeline labels: OpenAI is the default; Ollama is optional unless selected. Explain that an existing installation without an OpenAI key must set `BT_LLM_PROVIDER=ollama` before upgrading. Preserve the distinction between tested behavior and live-provider validation.
- [ ] Run focused tests from `server/`: `uv run python -m pytest -q tests/test_config.py tests/test_router.py tests/test_streaming.py tests/test_voice_routing.py tests/test_voice_prompt.py tests/test_gateway.py tests/test_chat_ws.py tests/test_system_prompt.py`.
- [ ] Run the full server suite from `server/`: `uv run python -m pytest -q`. Inspect `git diff --check` and the task's diff; leave unrelated changes untouched.
- [ ] With explicit approval for live calls/restarts, smoke-test text and voice in OpenAI mode while Ollama is unavailable. Confirm streaming, one tool call, and `compute="openai"`. Restart in Ollama mode and verify local routing. Do not execute mutating tools during the smoke test.

## Switching after implementation

Set `BT_LLM_PROVIDER=openai` or `BT_LLM_PROVIDER=ollama` in the server environment and restart BT through the installation's normal launcher. No app rebuild or conversation migration is needed. Environment variables already set by the launcher take precedence over `.env`.

**Risk:** OpenAI-default sends supplied history, recalled context, and tool results to OpenAI. Restarting interrupts active requests. Live credentials, configured model access, and voice behavior require separate smoke tests; mocked tests cannot establish those.
