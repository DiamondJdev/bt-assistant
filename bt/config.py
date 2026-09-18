"""
Central configuration, sourced from environment variables so the nixos
systemd unit and local dev both work without code changes.

Config is built lazily, on first access of `CONFIG` (or a call to
`get_config()`), rather than when this module is imported. That lets an
entry point load a .env file into os.environ before any value here is
actually read.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env_flag(name: str) -> bool:
	return os.environ.get(name, "") == "1"


def _dev_ui_default() -> bool:
	raw = os.environ.get("BT_DEVUI")
	if raw is not None:
		return raw == "1"
	return _env_flag("BT_DEVELOPER_MODE")


@dataclass(frozen=True)
class Config:
	# Local LLM (Ollama)
	ollama_base_url: str = field(default_factory=lambda: os.environ.get("BT_OLLAMA_URL", "http://127.0.0.1:11434"))
	ollama_model: str = field(default_factory=lambda: os.environ.get("BT_OLLAMA_MODEL", "qwen3:8b"))
	# ollama_model: str = os.environ.get("BT_OLLAMA_MODEL", "gpt-oss:20b") Heavy Model

	# Cloud fallback.
	openai_api_key: str | None = field(default_factory=lambda: os.environ.get("OPENAI_API_KEY"))
	openai_model: str = field(default_factory=lambda: os.environ.get("BT_OPENAI_MODEL", "gpt-5.6-luna"))

	# TTS (Model Responses)
	piper_voice: str = field(default_factory=lambda: os.environ.get("BT_PIPER_VOICE", "en_US-lessac-medium"))
	piper_binary: str = field(default_factory=lambda: os.environ.get("BT_PIPER_BIN", "piper"))

	# STT (User Inputs)
	whisper_model: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_MODEL", "small.en"))
	whisper_device: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_DEVICE", "auto"))

	# Storage (SQLite)
	db_path: str = field(default_factory=lambda: os.environ.get("BT_DB_PATH", "bt.sqlite3"))

	# Voice pipeline (Pipecat). Off unless explicitly enabled.
	voice_enabled: bool = field(default_factory=lambda: _env_flag("BT_VOICE"))
	whisper_compute_type: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_COMPUTE", "default"))

	# Developer toolings
	developer_mode: bool = field(default_factory=lambda: _env_flag("BT_DEVELOPER_MODE"))
	dev_ui_enabled: bool = field(default_factory=_dev_ui_default)

	# Ollama serves a native API at /api and an OpenAI-compatible one at /v1.
	# Callers pick the path so BT_OLLAMA_URL stays the only host setting.
	def ollama_url(self, path: str) -> str:
		return f"{self.ollama_base_url.rstrip('/')}/{path.lstrip('/')}"


_config: Config | None = None


def get_config() -> Config:
	global _config
	if _config is None:
		_config = Config()
	return _config


def __getattr__(name: str) -> Config:
	# Keeps `from bt.config import CONFIG` working everywhere without every
	# call site switching to get_config().
	if name == "CONFIG":
		return get_config()
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
