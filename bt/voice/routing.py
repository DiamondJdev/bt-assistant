"""
Per-turn local/cloud routing for the voice pipeline.
"""

from __future__ import annotations

from pipecat.frames.frames import Frame, LLMContextFrame, ManuallySwitchServiceFrame
from pipecat.pipeline.llm_switcher import LLMSwitcher
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.services.llm_service import LLMService

from bt.llm.router import wants_escalation


def _last_user_text(context: LLMContext) -> str:
	for message in reversed(context.get_messages()):
		if message.get("role") != "user":
			continue
		content = message.get("content")
		if isinstance(content, str):
			return content
		return " ".join(p.get("text", "") for p in content or [] if isinstance(p, dict))
	return ""


class EscalationRouter(FrameProcessor):
	def __init__(self, switcher: LLMSwitcher, local: LLMService, cloud: LLMService | None) -> None:
		super().__init__()
		self._local = local
		self._cloud = cloud
		self._requested: LLMService = switcher.strategy.active_service  # type: ignore[assignment]

	async def process_frame(self, frame: Frame, direction: FrameDirection) -> None:
		await super().process_frame(frame, direction)

		if isinstance(frame, LLMContextFrame) and self._cloud is not None:
			target = self._cloud if wants_escalation(_last_user_text(frame.context)) else self._local
			if target is not self._requested:
				self._requested = target
				await self.push_frame(ManuallySwitchServiceFrame(service=target), direction)

		await self.push_frame(frame, direction)
