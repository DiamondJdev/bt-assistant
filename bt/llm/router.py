"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local, escalating to cloud when the local response looks degenerate or
upon user request. See DESIGN.md "Routing: local vs. cloud" for the policy
in-depth.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import openai
from openai import AsyncOpenAI

from bt.config import CONFIG
from bt.personality.system_prompt import render_system_prompt
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

MAX_TOKENS = 2048

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
			client = AsyncOpenAI(base_url=CONFIG.ollama_url("v1"), api_key="ollama")
			_PROVIDERS[key] = Provider(key, CONFIG.ollama_model, client)
		else:
			if not CONFIG.openai_api_key:
				raise RuntimeError("Escalation requested but OPENAI_API_KEY is not set")
			client = AsyncOpenAI(api_key=CONFIG.openai_api_key)
			_PROVIDERS[key] = Provider(key, CONFIG.openai_model, client)
	return _PROVIDERS[key]


# Returns the whole assistant message including tool calls
async def _complete(
	provider: Provider, messages: list[Any], tools: list[dict[str, Any]] | None = None
):
	kwargs: dict[str, Any] = {"model": provider.model, "messages": messages}
	if tools:
		kwargs["tools"] = tools
	if provider.key == "openai":
		kwargs["max_completion_tokens"] = MAX_TOKENS
	else:
		kwargs["max_tokens"] = MAX_TOKENS

	resp = await provider.client.chat.completions.create(**kwargs)
	if not resp.choices:
		raise RuntimeError(f"{provider.key} returned no choices")
	return resp.choices[0].message


# Checks for bad model response. Content is None whenever the model asked for a
# tool instead of answering, so this only makes sense on a final message.
def _looks_degenerate(reply: str | None, user_text: str) -> bool:
	stripped = (reply or "").strip().lower()
	if not stripped or stripped == user_text.strip().lower():
		return True
	return stripped in ("i don't know", "i do not know", "i don't understand")


# Checks for user request for escalation
def _wants_escalation(user_text: str) -> bool:
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
) -> LLMResponse | None:
	escalated = provider == "cloud" or _wants_escalation(user_text)
	if escalated:
		log.info("starting on the cloud model")

	current = _provider("openai" if escalated else "ollama")
	working: list[Any] = [
		{"role": "system", "content": render_system_prompt(surface="text")},
		*messages,
	]
	tools = openai_tools() if ctx is not None and CONFIG.tools_enabled else None

	try:
		for _ in range(MAX_TOOL_ITERATIONS):
			message = await _complete(current, working, tools)

			if not message.tool_calls or ctx is None:
				if not escalated and _looks_degenerate(message.content, user_text):
					log.warning("local response looks degenerate, escalating to cloud")
					current, escalated = _provider("openai"), True
					continue
				return _result(message, current, ctx)

			working.append(_assistant_turn(message))
			for call in message.tool_calls:
				working.append({
					"role": "tool",
					"tool_call_id": call.id,
					"content": await dispatch_call(
						call.function.name, call.function.arguments, ctx
					),
				})

		log.warning("tool budget spent after %d rounds, answering without tools", MAX_TOOL_ITERATIONS)
		return _result(await _complete(current, working), current, ctx)
	except (openai.APIConnectionError, openai.APITimeoutError) as exc:
		if escalated:
			log.error("cloud call failed (%s)", exc)
			raise
		log.warning("local call failed (%s), escalating to cloud", exc)
		message = await _complete(_provider("openai"), working, tools)
		return _result(message, _provider("openai"), ctx)
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
	return LLMResponse(
		text=message.content or "",
		compute=provider.key,
		tools_used=tuple(ctx.used) if ctx else (),
	)
