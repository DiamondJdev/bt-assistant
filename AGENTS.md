# BT agent guide

BT is a local-first personal assistant. The Python/FastAPI hub handles chat through OpenAI by default (or Ollama with `BT_LLM_PROVIDER=ollama`, which keeps OpenAI escalation), SQLite transcripts, and streaming voice.

See `README.md` for setup and `docs/DESIGN.md` for design context.

`make run`, `make build MODE=debug|profile|release`, `make test [SUITE=swift|server|all] [FILTER=...]`, `make server` and `make logs` wrap the build, test and log commands; see `docs/DEVELOPMENT.md`. Debug and profile builds compile in `BT_DIAGNOSTICS` (Developer → Diagnostics… in the Mac app); release does not. Keep diagnostics content-free: timings and counts, never message text or tool arguments.

This is a monorepo. The Python backend lives in `server/`; run `uv` and test commands from there. `apple/BTKit/` holds the shared Swift package and tool sidebar; `apple/BTMac/` is the thin macOS app target in `apple/BT.xcodeproj`. Run package tests with `swift test --package-path apple/BTKit` from the repository root. `editors/vscode/` is the VS Code heartbeat extension for the Coding module (plain JavaScript, no dependencies); test it with `node --test editors/vscode/*.test.mjs` (a bare folder makes Node load `extension.js`). The Mac UI follows the "Sand Grid" spec in `design/HANDOFF.md` (mockups in `design/screens/`): tokens and shared components live in `apple/BTKit/Sources/BTKit/Design/`, the shared `AppStore` in `Store/`, and one folder per screen in `Screens/`. The BT screen talks to the server through `AppStore.chat` (`ChatModel`) once a server address is set in Settings, and shows sample threads until then. `docs/PLACEHOLDERS.md` lists what still runs on sample data. Remaining phases are planned in `docs/superpowers/plans/2026-10-19-monorepo-and-mac-client.md`.

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
- `swift test --package-path apple/BTKit` failing in CodeSign with "resource fork, Finder information, or similar detritus not allowed": macOS keeps adding a FinderInfo xattr under `~/Documents`. Build outside it: add `--scratch-path /tmp/btkit-build`.
- EventKit gives an occurrence a new `calendarItemIdentifier` when it's edited alone (`.thisEvent`) and gives later occurrences a new one after a `.futureEvents` split. Find events again by identifier plus occurrence date after every save; never keep identifiers across edits.
- `uv sync` may pick Python 3.15, which `ctranslate2` has no wheels for. Use `uv sync --python 3.14`.
- Claude Code agent worktrees branch from `main`, not the current branch. Reset a fresh worktree onto the intended base before building on it.
- Checking SwiftUI screens offscreen with `ImageRenderer` leaves `ScrollView`s blank and draws `TextField`s as yellow boxes. Check those in the running app.

Keep this section short. Add concrete mistakes and their fixes as they occur; never include secrets or private transcripts.
