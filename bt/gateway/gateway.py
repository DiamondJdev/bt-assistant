"""
Exposes assistant over Web

Must be assessible over tailscale for multiple devices to access the assistant
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from bt.config import CONFIG
from bt.llm.router import respond
from bt.tools.registry import default_context
from bt.transcript.store import Turn, get_store

log = logging.getLogger("bt.gateway")

app = FastAPI()
store = get_store()

if CONFIG.voice_enabled:
	log.info("Voice enabled, mounting voice routes")
	from bt.voice.routes import router as voice_router

	app.include_router(voice_router)

if CONFIG.dev_ui_enabled:
	log.info("Developer mode enabled, mounting DevUI routes")
	from bt.devui.routes import router as devui_router

	app.include_router(devui_router)


class ChatRequest(BaseModel):
	text: str
	session_id: str | None = None


class ChatResponse(BaseModel):
	session_id: str
	text: str
	compute: str
	tools_used: list[str] = []

@app.get("/health")
def health() -> dict[str, str]:
	return {"status": "ok"}

@app.get("/history")
async def get_history(session_id: str) -> list[Turn]:
	return await asyncio.to_thread(store.history, session_id)


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
	session_id = req.session_id or await asyncio.to_thread(store.new_session)
	try:
		await asyncio.to_thread(store.add_turn, session_id, "user", req.text, input_mode="text")
		history = await asyncio.to_thread(store.as_chat_messages, session_id)
		ctx = default_context(session_id, "text") if CONFIG.tools_enabled else None
		result = await respond(history, req.text, ctx=ctx)
		if not result:
			raise RuntimeError("LLM did not return a response")
		await asyncio.to_thread(store.add_turn, session_id, "bt", result.text, compute=result.compute)
		return ChatResponse(
			session_id=session_id,
			text=result.text,
			compute=result.compute,
			tools_used=list(result.tools_used),
		)
	except Exception as e:
		log.exception("chat request failed")
		raise HTTPException(status_code=502, detail=f"{session_id}: {e}") from e
