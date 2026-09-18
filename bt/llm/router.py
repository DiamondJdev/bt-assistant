"""
Router for model providers. Currently between local Ollama and cloud OpenAI.

Prefers local escalating to cloud when the local response looks degenerate or upon user request.
See DESIGN.md "Routing: local vs. cloud" for the policy in-depth.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from bt.config import CONFIG
from bt.personality.system_prompt import SYSTEM_PROMPT

log = logging.getLogger("bt.llm")

ESCALATION_PHRASES = (
    "think harder",
    "think about this more",
    "use your best model",
    "try this again",
    "escalate",
)


@dataclass
class LLMResponse:
    text: str
    compute: str  # 'ollama' | 'openai'

# Checks for bad model response
def _looks_degenerate(reply: str, user_text: str) -> bool:
    stripped = reply.strip()
    if not stripped or stripped.lower() == user_text.strip().lower():
        return True
    if stripped.lower() == "i don't know" or stripped.lower() == "i do not know" or stripped.lower() == "I don't understand":
        return True
    return False

# Checks for user request for escalation
def _wants_escalation(user_text: str) -> bool:
    lowered = user_text.lower()
    return any(phrase.lower() in lowered for phrase in ESCALATION_PHRASES)

async def _call_ollama(messages: list[dict]) -> str:
    payload = {
        "model": CONFIG.ollama_model,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}, *messages],
        "stream": False, # TODO: support streaming
    }
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(f"{CONFIG.ollama_base_url}/api/chat", json=payload)
        resp.raise_for_status()
        data = resp.json()
        return data["message"]["content"]


async def _call_openai(messages: list[dict]) -> str:
    if not CONFIG.openai_api_key:
        raise RuntimeError(
            "Escalation requested but OPENAI_API_KEY is not set"
        )
    import openai

    client = openai.AsyncOpenAI(api_key=CONFIG.openai_api_key)
    resp = await client.messages.create(
        model=CONFIG.openai_model,
        max_tokens=1024,
        system=SYSTEM_PROMPT,
        messages=messages,
    )
    return "".join(block.text for block in resp.content if block.type == "text") # TODO: support streaming

# Respond to a user message, using either the local Ollama model or the cloud OpenAI model
#
# message is prior chat history plus latest user input, in role/content form
async def respond(messages: list[dict], user_text: str, provider: str | None = "local") -> LLMResponse:
    provider = "local" | "cloud" | None

    if _wants_escalation(user_text):
        log.info("user requested escalation, calling cloud")
        provider = "cloud"

    try:
        if provider == "local":
            local_response = await _call_ollama(messages)
            if _looks_degenerate(local_response, user_text):
                log.warning("local response looks degenerate, escalating to cloud")
                provider = "cloud"
            else:
                return LLMResponse(text=local_response, compute="ollama")

        if provider == "cloud":
            cloud_response = await _call_openai(messages)
            return LLMResponse(text=cloud_response, compute="openai")
    except httpx.HTTPError as exc:
        log.warning("ollama call failed (%s), escalating to cloud", exc)
        return await respond(messages, user_text, "cloud") # call for another attempt with cloud provider
    except Exception as exc:
        log.exception("Unexpected error during LLM response: %s", exc)
        raise