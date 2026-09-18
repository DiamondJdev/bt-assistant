"""
WebSocket entry point for the voice pipeline.

Transport only, business logic handled by pipecat voice pipeline
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, WebSocket
from pipecat.workers.runner import WorkerRunner

from bt.transcript.store import get_store
from bt.voice.pipeline import build_worker

log = logging.getLogger("bt.voice")

router = APIRouter()


@router.websocket("/voice/ws")
async def voice_ws(websocket: WebSocket, session_id: str | None = None) -> None:
	await websocket.accept()
	store = get_store()
	session_id = session_id or await asyncio.to_thread(store.new_session)
	# Announce the session up front so the page can hand it to POST /chat.
	await websocket.send_json({"type": "session", "sessionId": session_id})

	history = await asyncio.to_thread(store.as_chat_messages, session_id)
	worker = build_worker(websocket, session_id, history)
	runner = WorkerRunner(handle_sigint=False)
	await runner.add_workers(worker)

	@worker.event_handler("on_client_disconnected")
	async def _on_disconnect(*_args) -> None:
		await runner.cancel()

	try:
		await runner.run()
	except Exception:
		log.exception("voice session %s failed", session_id)
