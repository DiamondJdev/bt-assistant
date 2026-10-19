"""One voice connection at a time keeps local model memory bounded."""

import asyncio
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pipecat.workers.runner import WorkerRunner

from bt.gateway.auth import authorized
from bt.transcript.store import get_store
from bt.voice.pipeline import build_worker, create_speech_services

log = logging.getLogger('bt.voice')
router = APIRouter()


@router.websocket('/voice/ws')
async def voice_ws(websocket: WebSocket, session_id: str | None = None):
    if not authorized(websocket):
        await websocket.accept()
        await websocket.close(code=1008)
        return
    await websocket.accept()
    state = websocket.app.state
    if state.voice_busy:
        await websocket.close(code=1013, reason='Another device is using voice')
        return
    store = get_store()
    session_id = session_id or await asyncio.to_thread(store.new_session)
    if state.voice_busy:
        await websocket.close(code=1013, reason='Another device is using voice')
        return
    runner = None
    try:
        with store.conversation(session_id):
            state.voice_busy = True
            try:
                await websocket.send_json({'type': 'session', 'sessionId': session_id})
                services = state.voice_services
                state.voice_services = None
                if services is None:
                    await websocket.send_json({'type': 'status', 'message': 'Loading voice models'})
                    services = await asyncio.to_thread(create_speech_services)
                history = await asyncio.to_thread(store.as_chat_messages, session_id)
                runner = WorkerRunner(handle_sigint=False)
                worker = build_worker(websocket, session_id, history, services, runner.cancel)

                @worker.event_handler('on_pipeline_error')
                async def pipeline_error(*_args):
                    if websocket.application_state.name == 'CONNECTED':
                        await websocket.send_json({'label': 'rtvi-ai', 'type': 'error'})

                await runner.add_workers(worker)
                await websocket.send_json({'type': 'ready'})
                await runner.run()
            finally:
                state.voice_busy = False
    except KeyError:
        await websocket.close(code=1008, reason='Conversation not found')
    except RuntimeError as exc:
        if runner is None and str(exc) == 'Conversation is busy':
            await websocket.close(code=1013, reason='Conversation is busy')
        else:
            log.exception('Voice session failed: %s', session_id)
            if websocket.application_state.name == 'CONNECTED':
                await websocket.close(code=1011, reason='Voice failed. Reconnect to retry.')
    except WebSocketDisconnect:
        pass
    except Exception:
        log.exception('Voice session failed: %s', session_id)
        if websocket.application_state.name == 'CONNECTED':
            await websocket.close(code=1011, reason='Voice failed. Reconnect to retry.')
    finally:
        if runner is not None:
            await runner.cancel()
