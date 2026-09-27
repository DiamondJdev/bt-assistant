"""
Per-turn local/cloud routing for the voice pipeline.

Mirrors bt/llm/router.py for voice: each turn goes to the local model unless the
Pilot asks for escalation. Routing happens before generation, so the local path
keeps full token streaming. The LLMSwitcher's failover strategy covers the
"local errors out" case (see DESIGN.md "Routing: local vs. cloud").
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
		# Multi-part content: join the text parts.
		return " ".join(p.get("text", "") for p in content or [] if isinstance(p, dict))
	return ""


# Sits directly before the LLMSwitcher. Switch frames are ControlFrames, so they
# stay ordered ahead of the context frame they route.
class EscalationRouter(FrameProcessor):
	def __init__(self, switcher: LLMSwitcher, local: LLMService, cloud: LLMService | None) -> None:
		super().__init__()
		self._local = local
		self._cloud = cloud
		# Tracks the last switch *requested*, not switcher.strategy.active_service:
		# switch frames are queued, so the switcher can lag a turn behind and
		# reading it back would skip a needed switch.
		self._requested: LLMService = switcher.strategy.active_service  # type: ignore[assignment]

	async def process_frame(self, frame: Frame, direction: FrameDirection) -> None:
		await super().process_frame(frame, direction)

		if isinstance(frame, LLMContextFrame) and self._cloud is not None:
			target = self._cloud if wants_escalation(_last_user_text(frame.context)) else self._local
			# The switcher refuses a service that failover marked unusable, so a
			# dead local model stays on cloud rather than bouncing back.
			if target is not self._requested:
				self._requested = target
				await self.push_frame(ManuallySwitchServiceFrame(service=target), direction)

		await self.push_frame(frame, direction)
