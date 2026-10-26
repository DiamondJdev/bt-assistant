"""
Central configuration, sourced from environment variables so the nixos
systemd unit and local dev both work without code changes.

Config is built lazily, on first access of `CONFIG` (or a call to
`get_config()`), rather than when this module is imported. That lets an
entry point load a .env file into os.environ before any value here is
actually read.
"""

from __future__ import annotations

import ipaddress
import os
from dataclasses import dataclass, field


def _env_flag(name: str) -> bool:
	return os.environ.get(name, "") == "1"


# Tailscale's IPv4 (CGNAT) and IPv6 ranges.
_TAILNET = (ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48"))


def _positive_int(name: str) -> int | None:
	raw = os.environ.get(name, "").strip()
	if not raw:
		return None
	if not raw.isdigit() or int(raw) <= 0:
		raise ValueError(f"{name} must be a positive whole number of tokens, got {raw!r}")
	return int(raw)


def _private_bind(host: str) -> bool:
	if host == "localhost":
		return True
	try:
		address = ipaddress.ip_address(host)
	except ValueError:
		return False
	return address.is_loopback or any(address in net for net in _TAILNET)


def _dev_ui_default() -> bool:
	raw = os.environ.get("BT_DEVUI")
	if raw is not None:
		return raw == "1"
	return _env_flag("BT_DEVELOPER_MODE")


def _openai_key() -> str | None:
	return (os.environ.get("OPENAI_API_KEY") or "").strip() or None


def _llm_provider_default() -> str:
	# Unset means OpenAI when a key exists, so Ollama-only installs keep starting.
	value = os.environ.get("BT_LLM_PROVIDER", "").strip().lower()
	return value or ("openai" if _openai_key() else "ollama")


@dataclass(frozen=True)
class Config:
	# Primary text and voice model: "openai" or "ollama". Read once at startup.
	llm_provider: str = field(default_factory=_llm_provider_default)

	# Local LLM (Ollama)
	ollama_base_url: str = field(default_factory=lambda: os.environ.get("BT_OLLAMA_URL", "http://127.0.0.1:11434"))
	ollama_model: str = field(default_factory=lambda: os.environ.get("BT_OLLAMA_MODEL", "qwen3:8b"))
	# ollama_model: str = os.environ.get("BT_OLLAMA_MODEL", "gpt-oss:20b") Heavy Model

	# Cloud model: primary in openai mode, escalation target in ollama mode.
	openai_api_key: str | None = field(default_factory=_openai_key)
	openai_model: str = field(default_factory=lambda: os.environ.get("BT_OPENAI_MODEL", "gpt-5.6-luna"))
	context_limit_provider: str | None = field(default_factory=lambda: os.environ.get("BT_CONTEXT_LIMIT_PROVIDER"))
	context_limit_model: str | None = field(default_factory=lambda: os.environ.get("BT_CONTEXT_LIMIT_MODEL"))
	# Only reported when provider and model match; see docs/DEVELOPMENT.md.
	context_limit: int | None = field(default_factory=lambda: _positive_int("BT_CONTEXT_LIMIT"))

	# TTS (Model Responses)
	piper_voice: str = field(default_factory=lambda: os.environ.get("BT_PIPER_VOICE", "en_US-lessac-medium"))
	piper_binary: str = field(default_factory=lambda: os.environ.get("BT_PIPER_BIN", "piper"))

	# STT (User Inputs)
	whisper_model: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_MODEL", "base.en"))
	whisper_device: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_DEVICE", "auto"))

	host: str = field(default_factory=lambda: os.environ.get("BT_HOST", "127.0.0.1"))

	# Operator's name, given to BT as a runtime fact when set.
	operator_name: str | None = field(default_factory=lambda: os.environ.get("BT_OPERATOR_NAME") or None)

	# Storage (SQLite)
	db_path: str = field(default_factory=lambda: os.environ.get("BT_DB_PATH", "bt.sqlite3"))

	# Memory (markdown files). Same CWD-relative convention as db_path above.
	memory_dir: str = field(default_factory=lambda: os.environ.get("BT_MEMORY_DIR", "memory"))

	# Tools. On by default, but the kill switch stays until the local model's
	# tool-calling has been exercised in anger.
	tools_enabled: bool = field(default_factory=lambda: os.environ.get("BT_TOOLS", "1") == "1")

	# Voice pipeline (Pipecat). Off unless explicitly enabled.
	voice_enabled: bool = field(default_factory=lambda: _env_flag("BT_VOICE"))
	whisper_compute_type: str = field(default_factory=lambda: os.environ.get("BT_WHISPER_COMPUTE", "default"))

	# Developer toolings
	developer_mode: bool = field(default_factory=lambda: _env_flag("BT_DEVELOPER_MODE"))
	dev_ui_enabled: bool = field(default_factory=_dev_ui_default)

	def validate_access(self) -> None:
		# BT has no login; the tailnet is the access boundary, so never listen beyond it.
		if not _private_bind(self.host):
			raise ValueError("BT_HOST must be loopback or a Tailscale address")

	@property
	def primary_model(self) -> str:
		return self.openai_model if self.llm_provider == "openai" else self.ollama_model

	def validate_llm(self) -> None:
		if self.llm_provider not in ("openai", "ollama"):
			raise ValueError(f"BT_LLM_PROVIDER must be openai or ollama, got {self.llm_provider!r}")
		if self.llm_provider == "openai" and not (self.openai_api_key or "").strip():
			raise ValueError("OPENAI_API_KEY is required when BT_LLM_PROVIDER=openai")

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
