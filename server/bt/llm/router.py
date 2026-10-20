"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local, escalating to cloud when the local response looks degenerate or
upon user request. See DESIGN.md "Routing: local vs. cloud" for the policy
in-depth.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

import openai
from openai import AsyncOpenAI

from bt.config import CONFIG
from bt.llm.streaming import completion_kwargs, stream_complete
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
				raise RuntimeError("Escalation requested but OPENAI_API_KEY is not set")
			client = AsyncOpenAI(api_key=CONFIG.openai_api_key, timeout=LLM_TIMEOUT_SECS, max_retries=1)
			_PROVIDERS[key] = Provider(key, CONFIG.openai_model, client)
	return _PROVIDERS[key]


# Returns the whole assistant message including tool calls
async def _complete(
	provider: Provider,
	messages: list[Any],
	tools: list[dict[str, Any]] | None = None,
	tool_choice: str | None = None,
):
	resp = await provider.client.chat.completions.create(**completion_kwargs(provider, messages, tools, tool_choice))
	if not resp.choices:
		raise ValueError(f"{provider.key} returned no choices")
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
) -> LLMResponse | None:
	if provider not in {None, "local", "cloud"}:
		raise ValueError("Unknown provider")
	escalated = provider == "cloud" or wants_escalation(user_text)
	if escalated:
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
		if on_delta is None:
			extra = {"tool_choice": tool_choice} if tool_choice else {}
			return await _complete(current, working, tools, **extra)
		# A mid-turn escalation stops deltas; the cloud reply arrives whole with the result.
		return await stream_complete(current, working, tools, tool_choice, on_text=stream_to)

	stream_to = on_delta
	try:
		for _ in range(MAX_TOOL_ITERATIONS):
			try:
				message = await complete()
			except (openai.APIError, ValueError) as exc:
				# Covers connection, timeout, status errors and malformed replies; tool turns so far are kept.
				if escalated:
					raise
				log.warning("local call failed (%s), escalating to cloud", exc)
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
				if name in client_names:
					content = await call_client(call.id, name, arguments)
					ctx.used.append(name)
				else:
					content = await dispatch_call(name, arguments, ctx)
				working.append({"role": "tool", "tool_call_id": call.id, "content": content})

		log.warning("tool budget spent after %d rounds, answering without tools", MAX_TOOL_ITERATIONS)
		# Tools stay declared so the tool turns above remain valid; "none" forces prose.
		return _result(await complete(tool_choice="none"), current, ctx)
	except Exception as exc:
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
