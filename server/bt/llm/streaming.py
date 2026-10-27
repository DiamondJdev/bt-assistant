"""Streamed completions: text arrives as it is written, tool calls are reassembled."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from types import SimpleNamespace
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
	from bt.llm.router import Provider
	from bt.llm.telemetry import CallMetrics

MAX_TOKENS = 2048
_OPEN, _CLOSE = "<think>", "</think>"


def completion_kwargs(
	provider: Provider,
	messages: list[Any],
	tools: list[dict[str, Any]] | None = None,
	tool_choice: str | None = None,
) -> dict[str, Any]:
	kwargs: dict[str, Any] = {"model": provider.model, "messages": messages}
	if tools:
		kwargs["tools"] = tools
		if tool_choice:
			kwargs["tool_choice"] = tool_choice
	if provider.key == "openai":
		kwargs["max_completion_tokens"] = MAX_TOKENS
	else:
		kwargs["max_tokens"] = MAX_TOKENS
	return kwargs


# Length of the longest end of text that could be the start of tag.
def _partial(text: str, tag: str) -> int:
	for n in range(min(len(text), len(tag) - 1), 0, -1):
		if tag.startswith(text[-n:]):
			return n
	return 0


class ThinkFilter:
	"""Drops <think>...</think> spans from streamed text, even when a tag is split across chunks."""

	def __init__(self) -> None:
		self._buf = ""
		self._inside = False
		self._started = False

	def feed(self, chunk: str) -> str:
		self._buf += chunk
		out = ""
		while True:
			tag = _CLOSE if self._inside else _OPEN
			at = self._buf.find(tag)
			if at >= 0:
				if not self._inside:
					out += self._buf[:at]
				self._buf = self._buf[at + len(tag):]
				self._inside = not self._inside
				continue
			keep = _partial(self._buf, tag)
			if not self._inside:
				out += self._buf[: len(self._buf) - keep]
			self._buf = self._buf[len(self._buf) - keep:]
			return self._emit(out)

	def flush(self) -> str:
		rest = "" if self._inside else self._buf
		self._buf = ""
		return self._emit(rest)

	# Thinking usually ends with blank lines; don't open a reply with them.
	def _emit(self, text: str) -> str:
		if not self._started:
			text = text.lstrip()
			self._started = bool(text)
		return text


async def stream_complete(
	provider: Provider,
	messages: list[Any],
	tools: list[dict[str, Any]] | None = None,
	tool_choice: str | None = None,
	on_text: Callable[[str], Awaitable[None]] | None = None,
	metrics: CallMetrics | None = None,
) -> SimpleNamespace:
	extra = {"stream_options": {"include_usage": True}} if metrics else {}
	stream = await provider.client.chat.completions.create(
		**completion_kwargs(provider, messages, tools, tool_choice), stream=True, **extra
	)
	think = ThinkFilter()
	parts: list[str] = []
	calls: list[dict[str, str]] = []
	by_index: dict[Any, dict[str, str]] = {}
	got_choice = False

	async for chunk in stream:
		if metrics:
			metrics.usage(getattr(chunk, "usage", None))
		if not chunk.choices:
			continue
		got_choice = True
		delta = chunk.choices[0].delta
		if metrics and (delta.content or delta.tool_calls or getattr(delta, "reasoning_content", None)):
			metrics.output()
		if delta.content:
			parts.append(delta.content)
			if on_text or metrics:
				if text := think.feed(delta.content):
					if metrics:
						metrics.visible()
					if on_text:
						await on_text(text)
		for piece in delta.tool_calls or ():
			entry = by_index.get(piece.index)
			# Some servers send each whole call at index 0; a new id means a new call.
			if entry is None or (piece.id and entry["id"] and piece.id != entry["id"]):
				entry = {"id": "", "name": "", "arguments": ""}
				by_index[piece.index] = entry
				calls.append(entry)
			entry["id"] = piece.id or entry["id"]
			if piece.function:
				entry["name"] = piece.function.name or entry["name"]
				entry["arguments"] += piece.function.arguments or ""

	if not got_choice:
		raise ValueError(f"{provider.key} returned no choices")
	if (on_text or metrics) and (text := think.flush()):
		if metrics:
			metrics.visible()
		if on_text:
			await on_text(text)
	return SimpleNamespace(
		content="".join(parts) or None,
		tool_calls=[
			SimpleNamespace(id=c["id"], function=SimpleNamespace(name=c["name"], arguments=c["arguments"]))
			for c in calls
		] or None,
	)
