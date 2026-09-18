# BT — Design

A voice-native assistant loosely based on BT-7274 from Titanfall 2, running with heavy providers
and ultra-thin consumers.

> I use my personal NixOS desktop to power this and I use my Macbook and iPhone as clients. Networking is handled via Tailscale on all devices.

## Decisions locked in

- **Compute**: hybrid, local-first. Check my NixOS config for my Ollama setup, but
  routine turns will run locally. ChatGPT `gpt-5.6-Luna` is the cloud escalation
  path for tool-heavy or reasoning-heavy
- **Scope, phase 1**: Desktop Hub Provider with thin MacOS Client, no external
  integrations (smart home, calendar, etc.) yet
- **Activation**: Three modes of activation:
  1. Wake Word: "Hey BT" and "BT" (I have two since just BT will likely unintentionally trigger often)
  2. Push-to-talk: Interface on clients to manually trigger BT instead of the wake word (think holding the power button on iPhones)
  3. Typed Text: All methods digest to text for cost/performance reasons, so this just bypasses the Speech to Text to Speech loop
- **Transcript**: Stored and served by server, clients simply stream to/from and render.

## Components

| Layer | Choice | Why |
| --- | --- | --- |
| Wake word | openWakeWord | Free, local, trainable custom wake word ("Hey BT") |
| STT | faster-whisper | Fast on GPU, good accuracy, easy Python API |
| LLM (local) | Ollama, model TBD (start: `qwen2.5:14b` or `llama3.1:8b`) | OpenAI-compatible API and ROCm compatible |
| LLM (cloud fallback) | ChatGPT 5.6 Luna via OpenAI API | Cheap, fast, and still capable for quick jobs |
| TTS | Piper (v1), evaluate Kokoro-82M later | Fast, cheap, CLI-driven, easy to swap |
| Transcript store | SQLite | Zero-ops, one file, easy to inspect/back up, good enough for now |
| Clients | TBD | Out of scope for now, needs to be multi-platform and accessible via tailscale tunneling |

## Routing: local vs. cloud

Default every turn to the local model. Escalate to ChatGPT 5.6 Luna when:

- the user explicitly asks BT to "think harder", "Escalate model", etc
— Local model response comes back malformed or errors-out.

This is a big UX impactor, so every transcript records which
backend answered it, for tuning later.

## Personality

`bt/personality/router.py` holds the system prompt attached to each message.
This will take tuning, so expect frequent changes.

> `SOUL.MD` modeled similar to OpenClaw and Hermes Agent approach?

## Open for phase 2+

- Tool/integration layer (system control, smart home, calendar) as
  LLM-callable functions once the conversational core is proven.
- Voice selection/tuning pass (Piper voice, or a designed/cloned voice).
