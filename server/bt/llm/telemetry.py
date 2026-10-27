from __future__ import annotations

import logging
import time
from collections.abc import Awaitable, Callable
from typing import Any
from uuid import uuid4

from bt.config import CONFIG
from bt.llm.streaming import MAX_TOKENS

log = logging.getLogger('bt.telemetry')


class CallMetrics:

	def __init__(self, provider: Any):
		self.started = time.monotonic()
		self.values: dict[str, Any] = {
			'call_id': str(uuid4()), 'provider': provider.key, 'model': provider.model,
			'status': 'running', 'output_limit': MAX_TOKENS,
		}
		if (CONFIG.context_limit_provider == provider.key
			and CONFIG.context_limit_model == provider.model
			and CONFIG.context_limit is not None and CONFIG.context_limit > 0):
			self.values['context_limit'] = CONFIG.context_limit

	def elapsed(self) -> float:
		return (time.monotonic() - self.started) * 1000

	def output(self) -> None:
		if 'first_output_ms' not in self.values:
			self.values['first_output_ms'] = self.elapsed()

	def visible(self) -> None:
		if 'first_visible_text_ms' not in self.values:
			self.values['first_visible_text_ms'] = self.elapsed()

	def usage(self, usage: Any) -> None:
		for key in ('prompt_tokens', 'completion_tokens'):
			value = getattr(usage, key, None)
			if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
				self.values[key] = value

	def finish(self, status: str) -> None:
		self.values.update(status=status, duration_ms=self.elapsed())
		count = self.values.get('completion_tokens')
		if count is not None and self.values['duration_ms'] > 0:
			self.values['tokens_per_second'] = count * 1000 / self.values['duration_ms']
			self.values['throughput_source'] = 'observed'

	def snapshot(self) -> dict[str, Any]:
		return {'duration_ms': self.elapsed(), **self.values}


class TurnMetrics:

	def __init__(self, turn_id: str, on_update: Callable[[dict[str, Any]], Awaitable[None]] | None = None):
		self.turn_id = turn_id
		self.started = time.monotonic()
		self.calls: list[CallMetrics] = []
		self.history_turns = 0
		self.context_chars = 0
		self.tool_wait_ms = 0.0
		self.tool_execution_ms = 0.0
		self.on_update = on_update
		self.status = 'running'

	def start_call(self, provider: Any) -> CallMetrics:
		call = CallMetrics(provider)
		self.calls.append(call)
		return call

	def tool_elapsed(self, call: CallMetrics, duration_ms: float, *, client: bool) -> None:
		if client:
			self.tool_wait_ms += duration_ms
			call.values['tool_wait_ms'] = call.values.get('tool_wait_ms', 0) + duration_ms
		else:
			self.tool_execution_ms += duration_ms

	def snapshot(self) -> dict[str, Any]:
		return {
			'status': self.status, 'duration_ms': (time.monotonic() - self.started) * 1000,
			'calls': [call.snapshot() for call in self.calls], 'tool_wait_ms': self.tool_wait_ms,
			'tool_execution_ms': self.tool_execution_ms,
			'history_turns': self.history_turns, 'context_chars': self.context_chars,
		}

	async def publish(self) -> None:
		if self.on_update:
			await self.on_update(self.snapshot())

	def finish(self, status: str) -> None:
		self.status = status
		log.info('text_chat_metrics turn_id=%s metrics=%s', self.turn_id, self.snapshot())
