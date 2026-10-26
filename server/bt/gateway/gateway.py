"""HTTP and voice access to the private assistant."""

from __future__ import annotations

import asyncio
import logging
import sqlite3
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from bt.config import CONFIG
from bt.gateway.chat_ws import ChatText
from bt.gateway.chat_ws import router as chat_ws_router
from bt.gateway.origin import OriginMiddleware
from bt.library import get_memory
from bt.llm.router import respond
from bt.tools.registry import default_context
from bt.transcript.store import Turn, get_store

log = logging.getLogger("bt.gateway")
store = get_store()
STATIC = Path(__file__).parents[1] / "client"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
	CONFIG.validate_access()
	CONFIG.validate_llm()
	app.state.voice_busy = False
	app.state.voice_services = None
	if CONFIG.voice_enabled:
		from bt.voice.routes import load_speech_services

		app.state.voice_services = load_speech_services()
		await app.state.voice_services  # fail startup if voice cannot load
	try:
		yield
	finally:
		app.state.voice_services = None
		store.close()


app = FastAPI(lifespan=lifespan)
app.add_middleware(OriginMiddleware)
app.include_router(chat_ws_router)
if STATIC.exists():
	app.mount("/static", StaticFiles(directory=STATIC), name="client")

if CONFIG.voice_enabled:
	from bt.voice.routes import router as voice_router

	app.include_router(voice_router)

if CONFIG.dev_ui_enabled:
	from bt.devui.routes import router as devui_router

	app.include_router(devui_router)


class ChatRequest(BaseModel):
	text: ChatText
	session_id: str | None = Field(default=None, max_length=128)


class ChatResponse(BaseModel):
	session_id: str
	text: str
	compute: str
	tools_used: list[str] = []


@app.get("/")
def client() -> FileResponse:
	return FileResponse(STATIC / "index.html")


@app.get("/health")
def health() -> dict[str, str]:
	return {"status": "ok"}


@app.get("/ready", response_model=None)
async def ready() -> dict | JSONResponse:
	try:
		await asyncio.to_thread(store.list_sessions)
		async with httpx.AsyncClient(timeout=5) as client:
			response = await client.get(CONFIG.ollama_url("/api/tags"))
			response.raise_for_status()
		names = {m["name"] for m in response.json()["models"]}
		if CONFIG.ollama_model not in names and f"{CONFIG.ollama_model}:latest" not in names:
			return _unavailable(f"Model {CONFIG.ollama_model} is not installed")
		return {"status": "ready", "voice_enabled": CONFIG.voice_enabled}
	except httpx.HTTPError:
		return _unavailable("Ollama is not reachable")
	except (ValueError, KeyError, TypeError, OSError, RuntimeError, sqlite3.Error):
		log.exception("readiness check failed")
		return _unavailable("Server check failed")


def _unavailable(reason: str) -> JSONResponse:
	return JSONResponse({"status": "unavailable", "reason": reason}, status_code=503)


@app.get("/config")
def config() -> dict[str, bool | str]:
	return {"voice_enabled": CONFIG.voice_enabled, "model": CONFIG.ollama_model}


@app.get("/sessions")
async def sessions() -> list[dict]:
	return await asyncio.to_thread(store.list_sessions)


@app.get("/memories")
async def memories() -> list[dict[str, str]]:
	index = await asyncio.to_thread(get_memory().index)
	return [{"name": m.name, "description": m.description, "type": m.type, "updated": m.updated} for m in index]


@app.post("/sessions")
async def new_session() -> dict[str, str]:
	return {"session_id": await asyncio.to_thread(store.new_session)}


@app.get("/history")
async def get_history(session_id: str) -> list[Turn]:
	try:
		return await asyncio.to_thread(store.history, session_id)
	except KeyError:
		raise HTTPException(404, "Conversation not found") from None


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
	session_id = req.session_id or await asyncio.to_thread(store.new_session)
	try:
		with store.conversation(session_id):
			try:
				await asyncio.to_thread(store.add_turn, session_id, "user", req.text, input_mode="text")
				history = await asyncio.to_thread(store.as_chat_messages, session_id)
				ctx = default_context(session_id, "text") if CONFIG.tools_enabled else None
				result = await respond(history, req.text, ctx=ctx, session_id=session_id)
				if not result:
					raise RuntimeError("LLM did not return a response")
				await asyncio.to_thread(store.add_turn, session_id, "bt", result.text, compute=result.compute)
				return ChatResponse(
					session_id=session_id,
					text=result.text,
					compute=result.compute,
					tools_used=list(result.tools_used),
				)
			except Exception:
				log.exception("chat request failed for %s", session_id)
				raise HTTPException(502, {"message": "Response failed. Try again.", "session_id": session_id}) from None
	except KeyError:
		raise HTTPException(404, "Conversation not found") from None
	except RuntimeError:
		raise HTTPException(409, "Conversation is busy. Disconnect voice or wait for the current reply.") from None
