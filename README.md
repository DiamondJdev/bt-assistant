# BT

A voice-native assistant with a personality inspired by BT-7274 from Titanfall 2.
See [DESIGN.md](./docs/DESIGN.md) for architecture and the decisions behind it.

## Status

Phase 1, in progress:

- text-mode conversational core
  - [x] Audio Capture
  - [x] Personality (SOUL.md)
  - [x] local/cloudLLM routing
  - [x] live transcript dashboard
- API interfacing
  - [x] Ollama (local)
  - [untested] OpenAI (cloudLLM)

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

Then copy .env.example, fill values, and start

```sh
cp .env.example .env
uv run bt
```

Use `uv run bt` for production or `uv run bt-dev` for testing enviroments.

### If not using Nix

```sh
tbd
```

Program is not yet tested on non-nixos installations
