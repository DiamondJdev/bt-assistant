"""
The voice pipeline: VAD -> STT -> LLM -> TTS, assembled with Pipecat.

Streaming is the point. The LLM is consumed token by token and TTS speaks each
sentence as it completes, so audio starts well before generation finishes.

TODO: Process on Client devices?
"""

from __future__ import annotations

import re

from num2words import num2words
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.worker import PipelineParams, PipelineWorker
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.frameworks.rtvi import (
	RTVIFunctionCallReportLevel,
	RTVIObserverParams,
)
from pipecat.processors.aggregators.llm_response_universal import (
	LLMContextAggregatorPair,
	LLMUserAggregatorParams,
)
from pipecat.transports.websocket.fastapi import (
	FastAPIWebsocketParams,
	FastAPIWebsocketTransport,
)
from pipecat.utils.text.skip_tags_aggregator import SkipTagsAggregator
from pipecat.utils.text.transforms.voice_formatter import VoiceFormatter

from bt.config import CONFIG
from bt.tools.registry import default_context, pipecat_tools
from bt.transcript.store import get_store
from bt.voice.persist import TranscriptObserver
from bt.voice.routing import RoutedLLMService
from bt.voice.serializer import JSONFrameSerializer

SAMPLE_RATE = 16_000

# stop_secs is relaxed here to allow for mid-sentence pauses in one turn
VAD_PARAMS = VADParams(confidence=0.7, start_secs=0.2, stop_secs=0.8, min_volume=0.4)

NO_SPEECH_PROB = 0.5 # Probability threshold for false positives in STT. Lower is more sensitive

# Primes Whisper with the assistant's name and punctuated style; add names it keeps misspelling
WHISPER_PROMPT = "Hey BT, what's on my calendar today? Remind me to call Mom at 5 p.m."

# ponytail: any 1500-2099 number is read as a year ("2000 users" too); add context checks if that misfires
YEAR_RE = re.compile(r"\b(1[5-9]\d\d|20\d\d)\b")

async def speak_years(text: str, _aggregation_type: str) -> str:
	return YEAR_RE.sub(lambda m: num2words(int(m.group()), to="year"), text)

# Applied in order to text just before Piper speaks it; transcripts keep the raw LLM text.
# Years run last so dates are already expanded by VoiceFormatter.
TEXT_TRANSFORMS = [("*", VoiceFormatter()), ("*", speak_years)]

def _vad() -> SileroVADAnalyzer:
	return SileroVADAnalyzer(sample_rate=SAMPLE_RATE, params=VAD_PARAMS)

def create_speech_services():
	# Model loading runs outside the event loop, before accepting voice traffic.
	from pipecat.services.whisper.stt import WhisperSTTService
	from pipecat.services.piper.tts import PiperTTSService

	stt = WhisperSTTService(
		device=CONFIG.whisper_device,
		compute_type=CONFIG.whisper_compute_type,
		settings=WhisperSTTService.Settings(model=CONFIG.whisper_model, no_speech_prob=NO_SPEECH_PROB, initial_prompt=WHISPER_PROMPT),
	)
	tts = PiperTTSService(
		settings=PiperTTSService.Settings(voice=CONFIG.piper_voice),
		text_transforms=TEXT_TRANSFORMS,
	)
	tts._text_aggregator = SkipTagsAggregator(tags=[("<think>", "</think>")])
	return stt, tts


def build_worker(websocket, session_id: str, history, speech_services, on_disconnect) -> PipelineWorker:
	transport = FastAPIWebsocketTransport(
		websocket=websocket,
		params=FastAPIWebsocketParams(
			audio_in_enabled=True,
			audio_out_enabled=True,
			audio_in_sample_rate=SAMPLE_RATE,
			audio_out_sample_rate=SAMPLE_RATE,
			add_wav_header=False,
			serializer=JSONFrameSerializer(),
		),
	)

	@transport.event_handler("on_client_disconnected")
	async def disconnected(*_args):
		await on_disconnect()

	stt, tts = speech_services
	llm = RoutedLLMService(session_id)
	tools = pipecat_tools() if CONFIG.tools_enabled else None

	# Conversation history
	context = (
		LLMContext(messages=history or [], tools=tools)
		if tools
		else LLMContext(messages=history or [])
	)

	# This owns the VADController which decides when a turn starts and stops.
	# NOTE: Frequent Cutoffs, Missed Speech, etc. are likely culprits of the VAD
	aggregators = LLMContextAggregatorPair(
		context,
		user_params=LLMUserAggregatorParams(vad_analyzer=_vad()),
	)

	pipeline = Pipeline([
		transport.input(),
		stt,
		aggregators.user(),
		llm,
		tts,
		transport.output(),
		aggregators.assistant(),
	])

	return PipelineWorker(
		pipeline,
		params=PipelineParams(
			enable_metrics=True, # Tracks and Passes metrics for DevUI
			enable_usage_metrics=True,

			# rates in Hz
			audio_in_sample_rate=SAMPLE_RATE,
			audio_out_sample_rate=SAMPLE_RATE,
		),
		app_resources=default_context(session_id, "voice") if tools else None,
		rtvi_observer_params=RTVIObserverParams(
			function_call_report_level={"*": RTVIFunctionCallReportLevel.FULL},
		),
		observers=[TranscriptObserver(get_store(), session_id, {llm: "ollama"})],
	)
