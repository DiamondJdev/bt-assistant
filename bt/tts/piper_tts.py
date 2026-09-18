"""
Text -> speech via Piper (CLI binary, invoked as a subprocess).
Piper writes a WAV; we play it with the system default output device.
"""

from __future__ import annotations

import logging
import subprocess
import tempfile
from pathlib import Path

from bt.config import CONFIG

log = logging.getLogger("bt.tts")


def synthesize_to_wav(text: str) -> Path:
    out = Path(tempfile.mkstemp(suffix=".wav"))
    # Run pipper CLI inline
    # TODO: This won't scale, make this more efficient
    proc = subprocess.run(
        [
            CONFIG.piper_binary,
            "--model",
            CONFIG.piper_voice,
            "--output_file",
            str(out),
        ],
        input=text.encode("utf-8"),
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"piper failed: {proc.stderr.decode(errors='replace')}")
    return out


def speak(text: str) -> None:
    # Synthesize and play immediately.
    # Swallows playback errors for gracefull text fallback
    wav_path = synthesize_to_wav(text)
    try:
        import sounddevice as sd
        import soundfile as sf

        data, samplerate = sf.read(str(wav_path))
        sd.play(data, samplerate)
        sd.wait()
    except Exception:
        log.exception("TTS playback failed")
    finally:
        wav_path.unlink(missing_ok=True)
