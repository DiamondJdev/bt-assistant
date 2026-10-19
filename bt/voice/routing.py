"""Local-first streaming with fallback before the first response token."""

import asyncio
from collections.abc import AsyncIterator

from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.services.ollama.llm import OLLamaLLMService
from pipecat.services.openai.llm import OpenAILLMService

from bt.config import CONFIG
from bt.llm.router import wants_escalation
from bt.personality.system_prompt import SYSTEM_PROMPT

CHUNK_TIMEOUT = 60  # seconds to wait for each streamed chunk
MAX_MESSAGES = 50


def _trim(context: LLMContext) -> None:
	# Bounds a long session's memory; starting on a user turn avoids orphaned replies.
	messages = context.get_messages()
	if len(messages) <= MAX_MESSAGES:
		return
	start = len(messages) - MAX_MESSAGES
	start = next((i for i in range(start, len(messages)) if messages[i].get("role") == "user"), start)
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


class RoutedLLMService(OLLamaLLMService):
	def __init__(self) -> None:
		super().__init__(
			base_url=CONFIG.ollama_url("v1"),
			settings=self.Settings(model=CONFIG.ollama_model, system_instruction=SYSTEM_PROMPT),
		)
		self.compute = "ollama"
		self._cloud = (
			OpenAILLMService(
				api_key=CONFIG.openai_api_key,
				settings=OpenAILLMService.Settings(model=CONFIG.openai_model, system_instruction=SYSTEM_PROMPT, max_completion_tokens=1024),
			)
			if CONFIG.openai_api_key
			else None
		)

	async def get_chat_completions(self, context: LLMContext) -> AsyncIterator:
		_trim(context)
		user_text = next((m.get("content", "") for m in reversed(context.get_messages()) if m.get("role") == "user"), "")
		use_cloud = isinstance(user_text, str) and wants_escalation(user_text)

		async def chunks():
			providers = [self._cloud] if use_cloud else [self, self._cloud]
			for provider in providers:
				if provider is None:
					raise RuntimeError("Cloud fallback requires OPENAI_API_KEY")
				stream = None
				emitted = False
				self.compute = "ollama" if provider is self else "openai"
				try:
					async with asyncio.timeout(CHUNK_TIMEOUT):
						stream = await (
							super(RoutedLLMService, self).get_chat_completions(context) if provider is self else provider.get_chat_completions(context)
						)
					async for chunk in _timed(stream):
						if chunk.choices and chunk.choices[0].delta.content:
							emitted = True
						yield chunk
					if not emitted:
						raise ValueError("Provider returned an empty response")
					return
				except Exception:
					# Retrying after speech starts would repeat a partial answer.
					if emitted or provider is not self or self._cloud is None:
						raise
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
