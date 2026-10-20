# BT agent guide

BT is a local-first personal assistant. The Python/FastAPI hub handles Ollama chat, optional OpenAI escalation, SQLite transcripts, and streaming voice.

See `README.md` for setup and `docs/DESIGN.md` for design context.

This is a monorepo. The Python backend lives in `server/`; run `uv` and test commands from there. `apple/` (SwiftUI macOS client, shared `BTKit` package) and `editors/` (heartbeat plugins) are planned in `docs/superpowers/plans/2026-10-19-monorepo-and-mac-client.md`.

## Module overview

Paths below are relative to `server/`.

| Module | Purpose |
| --- | --- |
| `bt/main.py`, `bt/dev_entry.py`, `bt/config.py` | Startup and environment configuration |
| `bt/gateway/` | HTTP API and route mounting |
| `bt/llm/` | Text model calls and local/cloud routing |
| `bt/transcript/` | SQLite sessions and conversation history |
| `bt/voice/` | Streaming voice pipeline, WebSocket audio, and transcript persistence |
| `bt/stt/`, `bt/tts/` | Direct speech recognition and playback helpers |
| `bt/client/`, `bt/devui/` | Browser client and developer dashboard |
| `bt/personality/` | Personality text in `SOUL.md` and system prompt loading |

## Learned mistakes/behaviors

Keep this section updated with mistakes you've made or behaviors that future agents will find useful when working in this proejct

- Text and voice use separate model paths. Check both when changing routing; editing direct STT/TTS helpers does not change the Pipecat voice pipeline.
- Configuration is cached. Load environment variables before first access and restart after changing settings. `.env.example` enables voice and developer tooling despite their code defaults being off.
- The local Qwen3 model (no_think) rarely chains a second tool call; it announces the next step and stops. Make one tool call return everything the answer needs (memory_search returns bodies for this reason).
- Keep the system prompt stable. Per-turn facts (time, turn, recalled memories) go on the latest user message via `turn_note`; a changing system prompt makes Ollama re-read the tools and whole history every turn.
- `ModuleNotFoundError: No module named 'bt'` from `uv run pytest` or `bt-dev`: macOS keeps marking the venv `.pth` files hidden and Python 3.14 skips them. Run tests with `uv run python -m pytest -q` from `server/`.
- `uv sync` may pick Python 3.15, which `ctranslate2` has no wheels for. Use `uv sync --python 3.14`.

Keep this section short. Add concrete mistakes and their fixes as they occur; never include secrets or private transcripts.
