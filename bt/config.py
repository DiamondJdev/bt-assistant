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
	ollama_model: str = os.environ.get("BT_OLLAMA_MODEL", "qwen3:8b")
	# ollama_model: str = os.environ.get("BT_OLLAMA_MODEL", "gpt-oss:20b") Heavy Model

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

	# Voice pipeline (Pipecat). Off unless explicitly enabled.
	voice_enabled: bool = os.environ.get("BT_VOICE", "") == "1"
	whisper_compute_type: str = os.environ.get("BT_WHISPER_COMPUTE", "default")

	# Developer toolings
	developer_mode: bool = os.environ.get("BT_DEVELOPER_MODE", "") == "1"
	dev_ui_enabled: bool = os.environ.get("BT_DEV", "") == developer_mode

	# Ollama serves a native API at /api and an OpenAI-compatible one at /v1.
	# Callers pick the path so BT_OLLAMA_URL stays the only host setting.
	def ollama_url(self, path: str) -> str:
		return f"{self.ollama_base_url.rstrip('/')}/{path.lstrip('/')}"

CONFIG = Config()
