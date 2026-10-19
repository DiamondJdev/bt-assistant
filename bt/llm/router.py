"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local, escalating to cloud when the local response looks degenerate or
upon user request. See DESIGN.md "Routing: local vs. cloud" for the policy
in-depth.
"""

from __future__ import annotations

import logging
import re
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
LLM_TIMEOUT_SECS = 60

_THINK_RE = re.compile(r"<think>.*?(?:</think>|\Z)", re.DOTALL)


def strip_thinking(text: str | None) -> str:
	return _THINK_RE.sub("", text or "").strip()

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
	kwargs: dict[str, Any] = {"model": provider.model, "messages": messages}
	if tools:
		kwargs["tools"] = tools
		if tool_choice:
			kwargs["tool_choice"] = tool_choice
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
) -> LLMResponse | None:
	escalated = provider == "cloud" or wants_escalation(user_text)
	if escalated:
		log.info("starting on the cloud model")

	current = _provider("openai" if escalated else "ollama")
	working: list[Any] = [
		{"role": "system", "content": render_system_prompt(surface="text", session_id=session_id, turns=_user_turns(messages))},
		*messages,
	]
	tools = openai_tools() if ctx is not None and CONFIG.tools_enabled else None

	try:
		for _ in range(MAX_TOOL_ITERATIONS):
			try:
				message = await _complete(current, working, tools)
			except openai.APIError as exc:
				# Covers connection, timeout and status errors; tool turns so far are kept.
				if escalated:
					raise
				log.warning("local call failed (%s), escalating to cloud", exc)
				current, escalated = _provider("openai"), True
				continue

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
		# Tools stay declared so the tool turns above remain valid; "none" forces prose.
		return _result(await _complete(current, working, tools, tool_choice="none"), current, ctx)
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
