"""
Records voice turns in the shared transcript, so all conversations stay in transcripts

This is an observer instead of a pipeline processor to ensure that the transcript remains complete
A processor would only see the frames at the end of the pipeline, which would be missing frames
"""

from __future__ import annotations

import asyncio

from pipecat.frames.frames import (
	LLMFullResponseEndFrame,
	LLMFullResponseStartFrame,
	LLMTextFrame,
	TranscriptionFrame,
)
from pipecat.observers.base_observer import BaseObserver, FramePushed
from pipecat.services.llm_service import LLMService
from pipecat.services.stt_service import STTService

from bt.transcript.store import TranscriptStore


class TranscriptObserver(BaseObserver):
	def __init__(self, store: TranscriptStore, session_id: str) -> None:
		super().__init__()
		self._store = store
		self._session_id = session_id
		self._reply: list[str] = []

	async def on_push_frame(self, data: FramePushed) -> None:
		frame, src = data.frame, data.source

		if isinstance(frame, TranscriptionFrame) and isinstance(src, STTService):
			await self._add_turn("user", frame.text, input_mode="voice_ptt")
			return

		if not isinstance(src, LLMService):
			return

		# Accumulated rather than written per sentence, so one reply is one row
		# and replaying the transcript doesn't yield a run of assistant turns.
		if isinstance(frame, LLMFullResponseStartFrame):
			self._reply.clear()
		elif isinstance(frame, LLMTextFrame):
			self._reply.append(frame.text)
		elif isinstance(frame, LLMFullResponseEndFrame):
			await self._add_turn("bt", "".join(self._reply), compute="ollama")
			self._reply.clear()

	async def _add_turn(self, role: str, text: str, **kwargs) -> None:
		if not text.strip():
			return
		await asyncio.to_thread(
			self._store.add_turn, self._session_id, role, text.strip(), **kwargs
		)
