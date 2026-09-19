"""
Developer Web UI. Only mounted in gateway.py when dev mode is enabled.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, HTMLResponse

from bt.config import CONFIG

STATIC = Path(__file__).parent / "static"

router = APIRouter(prefix="/dev")


@router.get("", response_class=HTMLResponse)
@router.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
	return HTMLResponse((STATIC / "index.html").read_text())


@router.get("/config")
def config() -> dict:
	return {
		"dev_mode_enabled": CONFIG.developer_mode,
		"ollama_model": CONFIG.ollama_model,
		"cloud_enabled": bool(CONFIG.openai_api_key),
		"piper_voice": CONFIG.piper_voice,
		"whisper_model": CONFIG.whisper_model,
		"voice_enabled": CONFIG.voice_enabled,
	}


@router.get("/static/{name}")
def static(name: str) -> FileResponse:
	path = (STATIC / name).resolve()
	if path.parent != STATIC.resolve() or not path.is_file():
		raise HTTPException(status_code=404)
	return FileResponse(path)
