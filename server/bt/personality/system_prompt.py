"""
Renders SOUL.md into a system prompt.

Voice reference: BT-7274 (Titanfall 2). Go play the game, its awesome
"""

from __future__ import annotations

import logging
import platform
from collections.abc import Mapping, Sequence
from datetime import datetime
from pathlib import Path

from bt.config import CONFIG
from bt.library import get_memory, recall

log = logging.getLogger("bt.personality")

SOUL_PATH = Path(__file__).with_name("SOUL.md")
TOOLS_MARKER = "<!-- bt:tools -->"
CONTEXT_MARKER = "<!-- bt:context -->"
NO_TOOLS = "No tools are available."
RECALL_LIMIT = 3
RECALL_TURNS = 2

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
	return _soul().replace(TOOLS_MARKER, "\n".join(tools) or NO_TOOLS).replace(
		CONTEXT_MARKER, "\n".join(context)
	)


# SOUL.md tells the model this section is authoritative
def _tool_lines(surface: str) -> list[str]:
	if not CONFIG.tools_enabled:
		return []
	# Imported here so the personality stays importable without pipecat.
	from bt.tools.registry import manifest_lines

	return manifest_lines(surface)

# Facts that hold for the whole session. Anything that changes per turn goes in turn_note,
# because a changed system prompt makes Ollama re-read the tool list and history.
def situation(surface: str) -> list[str]:
	lines = [
		f"You are running on {platform.node()}, a {platform.system()} host.",
		f"Your primary model is {CONFIG.openai_model} via OpenAI; some turns may use another model."
		if CONFIG.llm_provider == "openai"
		else f"Your primary model is {CONFIG.ollama_model} via Ollama; some turns may use another model.",
		"This turn is spoken aloud."
		if surface == "voice"
		else "This turn is delivered as text, not spoken.",
	]
	if CONFIG.operator_name:
		lines.append(f"Your operator is {CONFIG.operator_name}.")
	return lines + _memory_lines()


# Per-turn facts and the memories matching the request, so reads need no tool call.
def turn_note(
	user_text: str, *, session_id: str | None = None, turns: int | None = None, context: str | None = None
) -> str:
	now = datetime.now().astimezone()
	lines = [
		"Turn context, added by the system and not spoken by the Pilot.",
		f"The current date and time is {now.strftime('%H:%M on %A, %d %B %Y')}, timezone {now.tzname()}.",
	]
	if session_id:
		lines.append(f"Session {session_id}, turn {turns}." if turns else f"Session {session_id}.")
	try:
		found = get_memory().search(user_text, limit=RECALL_LIMIT)
	except OSError:
		log.warning("could not search the memory directory")
		found = []
	if found:
		lines.append("Stored memories matching this request. " + recall(found))
	if context:
		lines.append(f"App context: {context}")
	return " ".join(lines)


# Short replies like "Yes." match no memory, so recall also searches the turn they answer.
def recent_user_text(messages: Sequence[Mapping]) -> str:
	texts = [m["content"] for m in messages if m.get("role") == "user" and isinstance(m.get("content"), str)]
	return " ".join(texts[-RECALL_TURNS:])


# The end of the latest user message is the only spot after the cached system prompt, tools and history.
def with_turn_note(messages: Sequence[Mapping], note: str) -> list[Mapping]:
	last = max((i for i, m in enumerate(messages) if m.get("role") == "user"), default=None)
	if last is None or not isinstance(messages[last].get("content"), str):
		return list(messages)
	return [
		{**m, "content": f"{m['content']}\n\n{note}"} if i == last else m
		for i, m in enumerate(messages)
	]


def _memory_lines() -> list[str]:
	try:
		index = get_memory().index_lines()
	except OSError:
		log.warning("could not read the memory directory")
		return []
	if not index:
		return ["You have no stored memories yet."]
	return ["These memories are stored. Only the titles are shown below. Memories matching the latest request are attached to it as turn context; for any other, call memory_search before answering about it."] + index


def __getattr__(name: str) -> str:
	if name == "SYSTEM_PROMPT":
		return render_system_prompt()
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
