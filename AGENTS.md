# BT agent guide

BT is a local-first personal assistant. The Python/FastAPI hub handles Ollama chat, optional OpenAI escalation, SQLite transcripts, and streaming voice. See `README.md` for setup and `docs/DESIGN.md` for design context.

## Module overview

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

- Use separate worktrees when other agents are active. Worktrees exclude uncommitted changes; check the destination before integrating and leave others' work untouched.
- Text and voice use separate model paths. Check both when changing routing; editing direct STT/TTS helpers does not change the Pipecat voice pipeline.
- Configuration is cached. Load environment variables before first access and restart after changing settings. `.env.example` enables voice and developer tooling despite their code defaults being off.
- Design notes can describe planned or outdated behavior. Verify claims in source; `/health` confirms HTTP availability, not working models or audio.
- Keep this section short. Add concrete mistakes and their fixes as they occur; never include secrets or private transcripts.
