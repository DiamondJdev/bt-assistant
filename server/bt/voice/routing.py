"""Voice streaming with one provider switch per user turn, before output starts."""

import asyncio
import json
import logging
from collections.abc import AsyncIterator

from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.services.ollama.llm import OLLamaLLMService
from pipecat.services.openai.llm import OpenAILLMService

from bt.config import CONFIG
from bt.llm.router import wants_escalation
from bt.personality.system_prompt import recent_user_text, render_system_prompt, turn_note, with_turn_note

CHUNK_TIMEOUT = 60  # seconds to wait for each streamed chunk
# ~4k tokens at ~4 chars/token: with the ~2.3k-token prompt it leaves room for a reply in an 8k context.
MAX_HISTORY_CHARS = 16_000
# ponytail: fixed ~50k-token cap for OpenAI voice, size it per model if one ever needs more.
CLOUD_HISTORY_CHARS = 200_000
log = logging.getLogger("bt.voice.routing")
# Qwen3 soft switch; GGUF templates ignore reasoning_effort, and thinking ate the token budget.
NO_THINK = "\n\n/no_think"


def _trim(context: LLMContext, limit: int) -> None:
	# Overflowing the model context lets Ollama shift out the system prompt and tools, so budget by size.
	# Starting on a user turn avoids orphaned replies; an oversized current turn is kept whole.
	messages = context.get_messages()
	sizes = [len(json.dumps(m, default=str)) for m in messages]
	if sum(sizes) <= limit:
		return
	start, total = len(messages), 0
	while start > 0 and total + sizes[start - 1] <= limit:
		start -= 1
		total += sizes[start]
	users = [i for i, m in enumerate(messages) if m.get("role") == "user"]
	start = next((i for i in users if i >= start), users[-1] if users else start)
	context.set_messages(messages[start:])


async def _timed(stream) -> AsyncIterator:
	# The timeout wraps only the provider wait, never a yield, so a slow consumer can't trip it.
	iterator = stream.__aiter__()
	while True:
		try:
			async with asyncio.timeout(CHUNK_TIMEOUT):
				chunk = await anext(iterator)
		except StopAsyncIteration:
			return
		yield chunk


class _TurnNoted:
	# Per-turn facts ride on the outgoing request only, so the stored context stays clean.
	turn_note = ""

	def build_chat_completion_params(self, params_from_context) -> dict:
		params = super().build_chat_completion_params(params_from_context)
		if not self.turn_note:
			return params
		return {**params, "messages": with_turn_note(params["messages"], self.turn_note)}


class CloudLLMService(_TurnNoted, OpenAILLMService):
	def build_chat_completion_params(self, params_from_context) -> dict:
		params = super().build_chat_completion_params(params_from_context)
		if params["model"] == "gpt-5.6-luna" and params.get("tools"):
			params["reasoning_effort"] = "none"
		return params


class RoutedLLMService(_TurnNoted, OLLamaLLMService):
	def __init__(self, session_id: str | None = None) -> None:
		system = render_system_prompt(surface="voice")
		super().__init__(
			base_url=CONFIG.ollama_url("v1"),
			settings=self.Settings(model=CONFIG.ollama_model, system_instruction=system + NO_THINK),
		)
		self.session_id = session_id
		self.compute = "ollama"
		self._user_message = object()
		self._attempted_providers: set[str] = set()
		self._turn_output_started = False
		self._cloud = (
			CloudLLMService(
				api_key=CONFIG.openai_api_key,
				settings=OpenAILLMService.Settings(model=CONFIG.openai_model, system_instruction=system, max_completion_tokens=1024),
			)
			if CONFIG.openai_api_key
			else None
		)

	def _refresh_prompt(self, context: LLMContext) -> None:
		# No public per-turn hook: set pipecat's base and recompose so addons and later recomposes keep it.
		# The prompt only changes when memories do; per-turn facts go in the turn note.
		turns = sum(1 for m in context.get_messages() if m.get("role") == "user")
		system = render_system_prompt(surface="voice")
		note = turn_note(recent_user_text(context.get_messages()), session_id=self.session_id, turns=turns)
		for service in (self, self._cloud):
			if service is not None:
				service._base_system_instruction = system + (NO_THINK if service is self else "")
				service._compose_system_instruction()
				service.turn_note = note

	async def get_chat_completions(self, context: LLMContext) -> AsyncIterator:
		user_message = next((m for m in reversed(context.get_messages()) if m.get("role") == "user"), None)
		if user_message is not self._user_message:
			self._user_message = user_message
			self._attempted_providers.clear()
			self._turn_output_started = False
			user_text = user_message.get("content", "") if user_message else ""
			use_cloud = CONFIG.llm_provider == "openai" or (isinstance(user_text, str) and wants_escalation(user_text))
			self.compute = "openai" if use_cloud else "ollama"
		self._refresh_prompt(context)
		_trim(context, CLOUD_HISTORY_CHARS if self.compute == "openai" else MAX_HISTORY_CHARS)

		async def chunks():
			providers = [self._cloud, self] if self.compute == "openai" else [self, self._cloud]
			for index, provider in enumerate(providers):
				if provider is None:
					raise RuntimeError("OpenAI requires OPENAI_API_KEY")
				stream = None
				emitted = False
				self.compute = "ollama" if provider is self else "openai"
				self._attempted_providers.add(self.compute)
				if provider is self:
					_trim(context, MAX_HISTORY_CHARS)
				try:
					async with asyncio.timeout(CHUNK_TIMEOUT):
						stream = await (
							super(RoutedLLMService, self).get_chat_completions(context) if provider is self else provider.get_chat_completions(context)
						)
					async for chunk in _timed(stream):
						delta = chunk.choices[0].delta if chunk.choices else None
						# A tool call is a valid reply even with no text.
						if delta and (delta.content or getattr(delta, "tool_calls", None)):
							emitted = True
							self._turn_output_started = True
						if chunk.choices and getattr(chunk.choices[0], "finish_reason", None):
							log.info("voice reply ended: finish_reason=%s", chunk.choices[0].finish_reason)
						yield chunk
					if not emitted:
						raise ValueError("Provider returned an empty response")
					return
				except Exception:
					# Retrying after speech starts would repeat a partial answer.
					if self._turn_output_started or len(self._attempted_providers) > 1 or index == len(providers) - 1 or providers[index + 1] is None:
						raise
					log.warning("voice %s call failed, trying alternate provider", self.compute)
				finally:
					if stream is not None:
						await stream.close()

		return chunks()

	async def cleanup(self) -> None:
		await super().cleanup()
		await self._client.close()
		if self._cloud is not None:
			await self._cloud.cleanup()
			await self._cloud._client.close()
