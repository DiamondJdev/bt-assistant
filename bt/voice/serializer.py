"""
JSON wire format between the pipeline and a browser.

Quick internal tool for DevUI to convert incoming audio to protobuf and back,
so the page doesn't require a bundler.

Ugly AI code since this is an internal-only tool
"""

from __future__ import annotations

import base64
import json

from pipecat.frames.frames import (
	Frame,
	InputAudioRawFrame,
	OutputAudioRawFrame,
	OutputTransportMessageFrame,
	OutputTransportMessageUrgentFrame,
)
from pipecat.serializers.base_serializer import FrameSerializer


class JSONFrameSerializer(FrameSerializer):
	def __init__(self) -> None:
		# RTVI messages carry the transcripts and metrics the page exists to show,
		# so they must not be filtered out on their way to the client.
		super().__init__(params=FrameSerializer.InputParams(ignore_rtvi_messages=False))
		self._sample_rate = 16000

	async def setup(self, setup) -> None:
		self._sample_rate = setup.audio_out_sample_rate or self._sample_rate

	async def serialize(self, frame: Frame) -> str | None:
		if isinstance(frame, OutputAudioRawFrame):
			return json.dumps({
				"type": "audio",
				"pcm": base64.b64encode(frame.audio).decode(),
				"sampleRate": frame.sample_rate,
				"channels": frame.num_channels,
			})
		if isinstance(frame, (OutputTransportMessageFrame, OutputTransportMessageUrgentFrame)):
			return json.dumps(frame.message)
		return None

	async def deserialize(self, data: str | bytes) -> Frame | None:
		if len(data) > 64000:
			return None
		try:
			message = json.loads(data)
			if not isinstance(message, dict) or message.get("type") != "audio":
				return None
			rate = message.get("sampleRate", 16000)
			channels = message.get("channels", 1)
			if type(rate) is not int or rate != 16000 or type(channels) is not int or channels != 1:
				return None
			audio = base64.b64decode(message["pcm"], validate=True)
			if not audio or len(audio) % 2 or len(audio) > 32000:
				return None
			return InputAudioRawFrame(audio=audio, sample_rate=rate, num_channels=channels)
		except (ValueError, TypeError, KeyError):
			return None
