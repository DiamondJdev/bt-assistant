"""
Voice reference: BT-7274 (Titanfall 2). Go play the game, its awesome
"""

from __future__ import annotations
from pathlib import Path

SOUL_PATH = Path(__file__).with_name("SOUL.md")
SYSTEM_PROMPT = SOUL_PATH.read_text(encoding="utf-8")
