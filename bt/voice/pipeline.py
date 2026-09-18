"""
The voice pipeline: VAD -> STT -> LLM -> TTS, assembled with Pipecat.

Streaming is the point. The LLM is consumed token by token and TTS speaks each
sentence as it completes, so audio starts well before generation finishes.

TODO: Process on Client devices?
"""

from __future__ import annotations

from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.worker import PipelineParams, PipelineWorker
from pipecat.processors.aggregators.llm_context import LLMContext, LLMContextMessage
from pipecat.processors.aggregators.llm_response_universal import (
	LLMContextAggregatorPair,
	LLMUserAggregatorParams,
)
from pipecat.services.ollama.llm import OLLamaLLMService
from pipecat.services.piper.tts import PiperTTSService
from pipecat.services.whisper.stt import WhisperSTTService
from pipecat.transports.websocket.fastapi import (
	FastAPIWebsocketParams,
	FastAPIWebsocketTransport,
)
from pipecat.utils.text.skip_tags_aggregator import SkipTagsAggregator

from bt.config import CONFIG
from bt.personality.system_prompt import SYSTEM_PROMPT
from bt.transcript.store import get_store
from bt.voice.persist import TranscriptObserver
from bt.voice.serializer import JSONFrameSerializer

SAMPLE_RATE = 16_000

# stop_secs is relaxed here to allow for mid-sentence pauses in one turn
VAD_PARAMS = VADParams(confidence=0.7, start_secs=0.2, stop_secs=0.6, min_volume=0.6)

NO_SPEECH_PROB = 0.5 # Probability threshold for false positives in STT. Lower is more sensitive

def _vad() -> SileroVADAnalyzer:
	return SileroVADAnalyzer(sample_rate=SAMPLE_RATE, params=VAD_PARAMS)

# Constructs the voice pipeline for a single session (VAD->STT->LLM->TTS).
def build_worker(
	websocket, session_id: str, history: list[LLMContextMessage] | None = None
) -> PipelineWorker:
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

	stt = WhisperSTTService(
		device=CONFIG.whisper_device,
		compute_type=CONFIG.whisper_compute_type,
		settings=WhisperSTTService.Settings(
			model=CONFIG.whisper_model,
			no_speech_prob=NO_SPEECH_PROB,
		),
	)
	llm = OLLamaLLMService(
		base_url=CONFIG.ollama_url("v1"),
		settings=OLLamaLLMService.Settings(
			model=CONFIG.ollama_model,
			system_instruction=SYSTEM_PROMPT,
		),
	)
	tts = PiperTTSService(settings=PiperTTSService.Settings(voice=CONFIG.piper_voice))
	tts._text_aggregator = SkipTagsAggregator(tags=[("<think>", "</think>")]) # Filter out thinking from TTS responses to clients
	# Conversation history
	context = LLMContext(messages=history or [])

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
			# rate in Hz
			audio_in_sample_rate=SAMPLE_RATE,
			audio_out_sample_rate=SAMPLE_RATE,
		),
		observers=[TranscriptObserver(get_store(), session_id)],
	)
