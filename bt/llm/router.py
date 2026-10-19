"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local escalating to cloud when the local response looks degenerate or upon user request.
See DESIGN.md "Routing: local vs. cloud" for the policy in-depth.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

import httpx

from bt.config import CONFIG
from bt.personality.system_prompt import SYSTEM_PROMPT

from pipecat.processors.aggregators.llm_context import LLMContextMessage

log = logging.getLogger("bt.llm")

ESCALATION_PHRASES = (
	"think harder",
	"think about this more",
	"use your best model",
	"try this again",
	"escalate",
)


_THINK_RE = re.compile(r"<think>.*?(?:</think>|\Z)", re.DOTALL)


def strip_thinking(text: str) -> str:
	return _THINK_RE.sub("", text).strip()


@dataclass
class LLMResponse:
	text: str
	compute: str  # 'ollama' | 'openai'

# Checks for bad model response
def _looks_degenerate(reply: str, user_text: str) -> bool:
	stripped = reply.strip()
	if not stripped or stripped.lower() == user_text.strip().lower():
		return True
	if stripped.lower() == "i don't know" or stripped.lower() == "i do not know" or stripped.lower() == "i don't understand":
		return True
	return False

# Checks for user request for escalation
def wants_escalation(user_text: str) -> bool:
	lowered = user_text.lower()
	return any(phrase.lower() in lowered for phrase in ESCALATION_PHRASES)

async def _call_ollama(messages: list[LLMContextMessage]) -> str:
	payload = {
		"model": CONFIG.ollama_model,
		"messages": [{"role": "system", "content": SYSTEM_PROMPT}, *messages],
		"stream": False, # TODO: support streaming
	}
	async with httpx.AsyncClient(timeout=60) as client:
		resp = await client.post(CONFIG.ollama_url("/api/chat"), json=payload)
		resp.raise_for_status()
		data = resp.json()
		content = data["message"]["content"]
		if not isinstance(content, str):
			raise ValueError("Ollama response must contain text")
		return strip_thinking(content)


async def _call_openai(messages: list[LLMContextMessage]) -> str:
	if not CONFIG.openai_api_key:
		raise RuntimeError(
			"Escalation requested but OPENAI_API_KEY is not set"
		)
	import openai

	async with openai.AsyncOpenAI(api_key=CONFIG.openai_api_key, timeout=60, max_retries=1) as client:
		resp = await client.chat.completions.create(
			model=CONFIG.openai_model,
			max_completion_tokens=1024,
			messages=[{"role": "system", "content": SYSTEM_PROMPT}, *messages],  # type: ignore
		)
	# Checks for malformed response from API
	if not resp.choices or not resp.choices[0].message or not resp.choices[0].message.content:
		raise RuntimeError("OpenAI response missing choices or message")
	return strip_thinking(resp.choices[0].message.content) # TODO: support streaming

# Respond to a user message, using either the local Ollama model or the cloud OpenAI model
#
# message is prior chat history plus latest user input, in role/content form
async def respond(messages: list[LLMContextMessage], user_text: str, provider: str | None = "local") -> LLMResponse:
	if provider not in {None, "local", "cloud"}:
		raise ValueError("Unknown provider")
	if provider != "cloud" and not wants_escalation(user_text):
		try:
			local_response = await _call_ollama(messages)
			if not _looks_degenerate(local_response, user_text):
				return LLMResponse(text=local_response, compute="ollama")
		except (httpx.HTTPError, ValueError, KeyError, TypeError):
			log.warning("Local response failed; trying cloud", exc_info=True)
	cloud_response = await _call_openai(messages)
	if not cloud_response:
		raise ValueError("Cloud response is empty")
	return LLMResponse(text=cloud_response, compute="openai")
