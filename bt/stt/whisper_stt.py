"""
Speech to Text (SST) via faster-whisper (User Audio Input processing)

This proccesses methods 1 and 2 (wake-word and push-to-talk) of user audio input to text
for the LLM. This has plenty of room for error, so tuning the passive drain and delay is important.
"""

from __future__ import annotations

import logging

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

from bt.config import CONFIG

log = logging.getLogger("bt.stt")

# Sample rate for audio input in Hz
SAMPLE_RATE = 16_000

_model: WhisperModel | None = None

# Return Whisper Model
def _get_model() -> WhisperModel:
	global _model
	if _model is None:
		log.info("loading whisper model %s (device=%s)", CONFIG.whisper_model, CONFIG.whisper_device)
		_model = WhisperModel(CONFIG.whisper_model, device=CONFIG.whisper_device)
	return _model

# Records until silence with energy-based VAD stop. Returns np.ndarray of audio samples
def record_until_silence(max_seconds: float = 15.0, silence_ms: int = 900) -> np.ndarray:
	import collections

	frame_ms = 30
	frame_samples = int(SAMPLE_RATE * frame_ms / 1000)
	silence_frames_needed = silence_ms // frame_ms
	energy_threshold = 500.0  # TODO: tune threshold for better VAD, or swap away from manual approach

	buffer: list[np.ndarray] = []
	recent = collections.deque(maxlen=silence_frames_needed)

	with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="int16") as stream:
		frames_total = int(max_seconds * 1000 / frame_ms)
		for _ in range(frames_total):
			frame, _ = stream.read(frame_samples)
			buffer.append(frame.copy())
			energy = float(np.abs(frame.astype(np.float32)).mean())
			recent.append(energy < energy_threshold)
			if len(recent) == recent.maxlen and all(recent):
				break

	return np.concatenate(buffer).flatten().astype(np.float32) / 32768.0

# Convert audio input into text via Whisper.
def transcribe(audio: np.ndarray) -> str:
	model = _get_model()
	segments, _info = model.transcribe(audio, language="en")
	return " ".join(seg.text.strip() for seg in segments).strip()

# Wrapper for the two-step process: record until silence, then transcribe.
def listen_and_transcribe() -> str:
	audio = record_until_silence()
	return transcribe(audio)
