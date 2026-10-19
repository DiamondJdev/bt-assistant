"""One voice connection at a time keeps local model memory bounded."""

import asyncio
import logging
from contextlib import ExitStack

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pipecat.workers.runner import WorkerRunner
from starlette.datastructures import State

from bt.transcript.store import TranscriptStore, get_store
from bt.voice.pipeline import build_worker, create_speech_services

log = logging.getLogger("bt.voice")
router = APIRouter()


def _log_load_failure(task: asyncio.Future) -> None:
	if not task.cancelled() and task.exception():
		log.error("Voice model loading failed", exc_info=task.exception())


def load_speech_services() -> asyncio.Future:
	# Model loading runs in a thread; a pending load is shared, never duplicated.
	task = asyncio.ensure_future(asyncio.to_thread(create_speech_services))
	task.add_done_callback(_log_load_failure)
	return task


async def _run_session(websocket: WebSocket, state: State, store: TranscriptStore, session_id: str) -> None:
	await websocket.send_json({"type": "session", "sessionId": session_id})
	loading = state.voice_services or load_speech_services()
	state.voice_services = None
	if not loading.done():
		await websocket.send_json({"type": "status", "message": "Loading voice models"})
	services = await loading
	history = await asyncio.to_thread(store.as_chat_messages, session_id)
	runner = WorkerRunner(handle_sigint=False)
	try:
		worker = build_worker(websocket, session_id, history, services, runner.cancel)

		@worker.event_handler("on_pipeline_error")
		async def pipeline_error(*_args) -> None:
			if websocket.application_state.name == "CONNECTED":
				await websocket.send_json({"label": "rtvi-ai", "type": "error"})

		await runner.add_workers(worker)
		await websocket.send_json({"type": "ready"})
		await runner.run()
	finally:
		await runner.cancel()


@router.websocket("/voice/ws")
async def voice_ws(websocket: WebSocket, session_id: str | None = None) -> None:
	# AccessMiddleware has already checked the token and origin.
	await websocket.accept()
	state = websocket.app.state
	store = get_store()
	# Re-checked after the await below; nothing awaits between that check and the lease.
	if not state.voice_busy:
		session_id = session_id or await asyncio.to_thread(store.new_session)
	if state.voice_busy:
		await websocket.close(code=1013, reason="Another device is using voice")
		return
	with ExitStack() as lease:
		try:
			lease.enter_context(store.conversation(session_id))
		except KeyError:
			await websocket.close(code=1008, reason="Conversation not found")
			return
		except RuntimeError:
			await websocket.close(code=1013, reason="Conversation is busy")
			return
		state.voice_busy = True
		try:
			await _run_session(websocket, state, store, session_id)
		except WebSocketDisconnect:
			pass
		except Exception:
			log.exception("Voice session failed: %s", session_id)
			if websocket.application_state.name == "CONNECTED":
				await websocket.close(code=1011, reason="Voice failed. Reconnect to retry.")
		finally:
			state.voice_busy = False
			# Pipecat cleans up services with the pipeline; prepare fresh ones for the next connection.
			if state.voice_services is None:
				state.voice_services = load_speech_services()
