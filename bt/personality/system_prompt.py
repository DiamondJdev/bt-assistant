"""
Renders SOUL.md into a system prompt.

Voice reference: BT-7274 (Titanfall 2). Go play the game, its awesome
"""

from __future__ import annotations

import logging
import platform
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path

from bt.config import CONFIG
from bt.library import get_memory

log = logging.getLogger("bt.personality")

SOUL_PATH = Path(__file__).with_name("SOUL.md")
TOOLS_MARKER = "<!-- bt:tools -->"
CONTEXT_MARKER = "<!-- bt:context -->"

_SOUL: str | None = None


def _soul() -> str:
	global _SOUL
	if _SOUL is None:
		_SOUL = SOUL_PATH.read_text(encoding="utf-8")
	return _SOUL

def render_system_prompt(
	*,
	surface: str = "text",
	tools: Sequence[str] | None = None,
	context: Sequence[str] | None = None,
) -> str:
	if tools is None:
		tools = _tool_lines(surface)
	if context is None:
		context = situation(surface)
	return _soul().replace(TOOLS_MARKER, "\n".join(tools)).replace(
		CONTEXT_MARKER, "\n".join(context)
	)


# SOUL.md tells the model this section is authoritative
def _tool_lines(surface: str) -> list[str]:
	if not CONFIG.tools_enabled:
		return []
	# Imported here so the personality stays importable without pipecat.
	from bt.tools.registry import manifest_lines

	return manifest_lines(surface)

# This populates situation context without requiring a full tool-call
def situation(surface: str) -> list[str]:
	now = datetime.now().astimezone()
	lines = [
		f"The current date and time is {now.strftime('%H:%M on %A, %d %B %Y')}, "
		f"timezone {now.tzname()}.",
		f"You are running on {platform.node()}, a {platform.system()} host.",
		f"Your local model is {CONFIG.ollama_model}.",
		"This turn is spoken aloud."
		if surface == "voice"
		else "This turn is delivered as text, not spoken.",
	]

	for line in _memory_lines():
		lines.append(line)
	return lines


def _memory_lines() -> list[str]:
	try:
		index = get_memory().index_lines()
	except OSError:
		log.warning("could not read the memory directory")
		return []
	if not index:
		return ["You have no stored memories yet."]
	return ["These memories are stored. Use memory_read for the full text of one."] + index


def __getattr__(name: str) -> str:
	if name == "SYSTEM_PROMPT":
		return render_system_prompt()
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
