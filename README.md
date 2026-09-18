# BT

A voice-native assistant with a personality inspired by BT-7274 from Titanfall 2.
See [DESIGN.md](./docs/DESIGN.md) for architecture and the decisions behind it.

## Status

Phase 1, in progress:

- text-mode conversational core
  - [] Audio Capture
  - [] Personality (SOUL.md)
  - [] local/cloudLLM routing
  - [] live transcript dashboard
- API interfacing
  - [] Ollama (local)
  - [] OpenAI (cloudLLM)

## Quickstart (dev)

### If on Nix

```sh
nix develop # devShell: python, uv, ffmpeg, portaudio, piper-tts
uv sync
```

`services.ollama` must be enabled and running (See [my Nixos config](https://github.com/diamondjdev/nixos)
if you'd like to see how it works in my workflow) with the perfered model pulled.

eg:

```sh
ollama pull qwen2.5:14b
```

Then add API key and start

```sh
export OPENAI_API_KEY=... # optional, only needed for cloud escalation
uv run bt
```

program is accessible on [localhost:8765](https://127.0.0.1:8765)

### If not using Nix

```sh
tbd
```

Program is not yet tested on non-nixos installations
