"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local, escalating to cloud when the local response looks degenerate or
upon user request. See DESIGN.md "Routing: local vs. cloud" for the policy
in-depth.
"""

from __future__ import annotations

import logging
import re
import asyncio
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

import openai
from openai import AsyncOpenAI

from bt.config import CONFIG
from bt.llm.streaming import completion_kwargs, stream_complete
from bt.llm.telemetry import CallMetrics, TurnMetrics
from bt.personality.system_prompt import recent_user_text, render_system_prompt, turn_note, with_turn_note
from bt.tools.registry import ToolContext, dispatch_call, openai_tools

from pipecat.processors.aggregators.llm_context import LLMContextMessage

log = logging.getLogger("bt.llm")

ESCALATION_PHRASES = (
	"think harder",
	"think about this more",
	"use your best model",
	"try this again",
	"escalate",
)

LLM_TIMEOUT_SECS = 60

_THINK_RE = re.compile(r"<think>.*?(?:</think>|\Z)", re.DOTALL)


def strip_thinking(text: object) -> str:
	# Anything but a string (None, a malformed list) counts as no reply.
	return _THINK_RE.sub("", text).strip() if isinstance(text, str) else ""

# WARN: This could falsely trigger on a valid response
MAX_TOOL_ITERATIONS = 6


@dataclass
class LLMResponse:
	text: str
	compute: str  # 'ollama' | 'openai'
	tools_used: tuple[str, ...] = ()


@dataclass(frozen=True)
class Provider:
	key: str
	model: str
	client: AsyncOpenAI

_PROVIDERS: dict[str, Provider] = {}

def _provider(key: str) -> Provider:
	if key not in _PROVIDERS:
		if key == "ollama":
			# Ollama ignores the key, but the SDK insists on one being present.
			client = AsyncOpenAI(base_url=CONFIG.ollama_url("v1"), api_key="ollama", timeout=LLM_TIMEOUT_SECS, max_retries=1)
			_PROVIDERS[key] = Provider(key, CONFIG.ollama_model, client)
		else:
			if not CONFIG.openai_api_key:
				raise RuntimeError("OPENAI_API_KEY is not set")
			client = AsyncOpenAI(api_key=CONFIG.openai_api_key, timeout=LLM_TIMEOUT_SECS, max_retries=1)
			_PROVIDERS[key] = Provider(key, CONFIG.openai_model, client)
	return _PROVIDERS[key]


# Returns the whole assistant message including tool calls
async def _complete(
	provider: Provider,
	messages: list[Any],
	tools: list[dict[str, Any]] | None = None,
	tool_choice: str | None = None,
	metrics: CallMetrics | None = None,
):
	resp = await provider.client.chat.completions.create(**completion_kwargs(provider, messages, tools, tool_choice))
	if metrics:
		metrics.usage(getattr(resp, "usage", None))
	if not resp.choices:
		raise ValueError(f"{provider.key} returned no choices")
	if metrics:
		message = resp.choices[0].message
		if message.content or message.tool_calls:
			metrics.output()
		if strip_thinking(message.content):
			metrics.visible()
	return resp.choices[0].message


# Checks for bad model response. Content is None whenever the model asked for a
# tool instead of answering, so this only makes sense on a final message.
def _looks_degenerate(reply: str | None, user_text: str) -> bool:
	stripped = strip_thinking(reply).lower()
	if not stripped or stripped == user_text.strip().lower():
		return True
	return stripped in ("i don't know", "i do not know", "i don't understand")


def _user_turns(messages: list[Any]) -> int:
	return sum(1 for m in messages if m.get("role") == "user")


# Checks for user request for escalation
def wants_escalation(user_text: str) -> bool:
	lowered = user_text.lower()
	return any(phrase.lower() in lowered for phrase in ESCALATION_PHRASES)


# Respond to a user message, using either the local Ollama model or the cloud
# OpenAI model.
#
# messages is prior chat history plus latest user input, in role/content form.
async def respond(
	messages: list[LLMContextMessage],
	user_text: str,
	provider: str | None = None,
	ctx: ToolContext | None = None,
	session_id: str | None = None,
	*,
	context: str | None = None,
	on_delta: Callable[[str], Awaitable[None]] | None = None,
	client_tools: list[dict[str, Any]] | None = None,
	call_client: Callable[[str, str, str], Awaitable[str]] | None = None,
	telemetry: TurnMetrics | None = None,
) -> LLMResponse | None:
	if provider not in {None, "local", "cloud"}:
		raise ValueError("Unknown provider")
	# On the cloud there are no local heuristics or fallback; only an Ollama-mode escalation is logged.
	primary_cloud = provider != "local" and CONFIG.llm_provider == "openai"
	escalated = primary_cloud or provider == "cloud" or wants_escalation(user_text)
	if escalated and not primary_cloud:
		log.info("starting on the cloud model")

	current = _provider("openai" if escalated else "ollama")
	note = turn_note(recent_user_text(messages), session_id=session_id, turns=_user_turns(messages), context=context)
	working: list[Any] = [
		{"role": "system", "content": render_system_prompt(surface="text")},
		*with_turn_note(messages, note),
	]
	tools = None
	client_names: set[str] = set()
	if ctx is not None and CONFIG.tools_enabled:
		tools = openai_tools() + list(client_tools or ())
		client_names = {t["function"]["name"] for t in client_tools or ()}

	async def complete(tool_choice: str | None = None):
		nonlocal active_call
		active_call = telemetry.start_call(current) if telemetry else None
		extra = {"metrics": active_call} if active_call else {}
		try:
			if on_delta is None:
				if tool_choice:
					extra['tool_choice'] = tool_choice
				message = await _complete(current, working, tools, **extra)
			else:
				message = await stream_complete(current, working, tools, tool_choice, on_text=stream_to, **extra)
		except BaseException as exc:
			if active_call:
				active_call.finish('cancelled' if isinstance(exc, asyncio.CancelledError) else 'error')
			raise
		if active_call:
			active_call.finish('completed')
			await telemetry.publish()
		return message

	active_call = None
	stream_to = on_delta
	try:
		for _ in range(MAX_TOOL_ITERATIONS):
			try:
				message = await complete()
			except (openai.APIError, ValueError) as exc:
				# Covers connection, timeout, status errors and malformed replies; tool turns so far are kept.
				if escalated:
					raise
				log.warning("local call failed (%s), escalating to cloud", type(exc).__name__ if telemetry else exc)
				current, escalated, stream_to = _provider("openai"), True, None
				continue

			if not message.tool_calls or ctx is None:
				if not escalated and _looks_degenerate(message.content, user_text):
					log.warning("local response looks degenerate, escalating to cloud")
					current, escalated, stream_to = _provider("openai"), True, None
					continue
				return _result(message, current, ctx)

			working.append(_assistant_turn(message))
			for call in message.tool_calls:
				name, arguments = call.function.name, call.function.arguments
				started = time.monotonic() if telemetry else None
				try:
					if name in client_names:
						content = await call_client(call.id, name, arguments)
						ctx.used.append(name)
					else:
						content = await dispatch_call(name, arguments, ctx)
				finally:
					if telemetry and active_call:
						telemetry.tool_elapsed(active_call, (time.monotonic() - started) * 1000, client=name in client_names)
				if telemetry:
					await telemetry.publish()
				working.append({"role": "tool", "tool_call_id": call.id, "content": content})

		log.warning("tool budget spent after %d rounds, answering without tools", MAX_TOOL_ITERATIONS)
		# Tools stay declared so the tool turns above remain valid; "none" forces prose.
		return _result(await complete(tool_choice="none"), current, ctx)
	except Exception as exc:
		if telemetry:
			log.error("LLM response failed turn_id=%s error_type=%s", telemetry.turn_id, type(exc).__name__)
		else:
			log.exception("Unexpected error during LLM response: %s", exc)
		raise

def _assistant_turn(message) -> dict[str, Any]:
	return {
		"role": "assistant",
		"content": message.content or "",
		"tool_calls": [
			{
				"id": call.id,
				"type": "function",
				"function": {
					"name": call.function.name,
					"arguments": call.function.arguments,
				},
			}
			for call in message.tool_calls
		],
	}


def _result(message, provider: Provider, ctx: ToolContext | None) -> LLMResponse:
	text = strip_thinking(message.content)
	if not text:
		raise ValueError(f"{provider.key} returned an empty reply")
	return LLMResponse(
		text=text,
		compute=provider.key,
		tools_used=tuple(ctx.used) if ctx else (),
	)
