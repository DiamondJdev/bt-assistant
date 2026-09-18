# Dev entry point (`bt-dev`).
# Loads shellVar -> .env.dev -> .env in order

from __future__ import annotations

from pathlib import Path

from dotenv import load_dotenv

_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(_ROOT / ".env.dev", override=False)

from bt.main import run

__all__ = ["run"]
