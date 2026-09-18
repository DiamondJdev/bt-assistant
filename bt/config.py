"""
Central configuration, sourced from environment variables so the nixos
systemd unit and local dev both work without code changes.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    # Local LLM (Ollama)
    ollama_base_url: str = os.environ.get("BT_OLLAMA_URL", "http://127.0.0.1:11434")
    ollama_model: str = os.environ.get("BT_OLLAMA_MODEL", "qwen2.5:14b")

    # Cloud fallback.
    openai_api_key: str | None = os.environ.get("OPENAI_API_KEY")
    openai_model: str = os.environ.get("BT_OPENAI_MODEL", "gpt-5.6-luna")

    # TTS (Model Responses)
    piper_voice: str = os.environ.get("BT_PIPER_VOICE", "en_US-lessac-medium")
    piper_binary: str = os.environ.get("BT_PIPER_BIN", "piper")

    # STT (User Inputs)
    whisper_model: str = os.environ.get("BT_WHISPER_MODEL", "small.en")
    whisper_device: str = os.environ.get("BT_WHISPER_DEVICE", "auto")

    # Storage (SQLite)
    db_path: str = os.environ.get("BT_DB_PATH", "bt.sqlite3")

CONFIG = Config()
