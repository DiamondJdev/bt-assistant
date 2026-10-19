from types import SimpleNamespace

import pytest
from starlette.websockets import WebSocketDisconnect

from bt.gateway import gateway
from bt.voice import routes
from test_gateway import client, login

# Voice transport is tested without downloading models or invoking inference.
gateway.app.include_router(routes.router)


@pytest.fixture(autouse=True)
def voice_runtime(monkeypatch):
    monkeypatch.setattr(routes, 'get_store', lambda: gateway.store)
    class Runner:
        def __init__(self, **kw):
            pass
        async def add_workers(self, worker):
            self.socket = worker.socket
        async def run(self):
            await self.socket.receive()
        async def cancel(self):
            pass
    monkeypatch.setattr(routes, 'WorkerRunner', Runner)
    def build(socket, *args):
        return SimpleNamespace(socket=socket, event_handler=lambda name: lambda fn: fn)
    monkeypatch.setattr(routes, 'build_worker', build)


def test_voice_rejects_missing_token_and_wrong_origin(client):
    with client.websocket_connect('wss://testserver/voice/ws') as ws:
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
        assert exc.value.code == 1008
    login(client)
    with client.websocket_connect('wss://testserver/voice/ws', headers={'Origin': 'https://evil.example'}) as ws:
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
        assert exc.value.code == 1008


def test_voice_holds_conversation_lease_and_limits_connections(client, monkeypatch):
    login(client)
    sid = client.post('/sessions').json()['session_id']
    monkeypatch.setattr(routes, 'create_speech_services', lambda: ())
    with client.websocket_connect(f'wss://testserver/voice/ws?session_id={sid}') as ws:
        assert ws.receive_json()['sessionId'] == sid
        while ws.receive_json()['type'] != 'ready':
            pass
        assert client.post('/chat', json={'text': 'hello', 'session_id': sid}).status_code == 409
        with client.websocket_connect('wss://testserver/voice/ws') as other:
            with pytest.raises(WebSocketDisconnect) as exc:
                other.receive_json()
            assert exc.value.code == 1013
    with gateway.store.conversation(sid):
        assert gateway.app.state.voice_busy is False


def test_failed_voice_setup_releases_capacity_and_session(client, monkeypatch):
    login(client)
    sid = client.post('/sessions').json()['session_id']
    def fail():
        raise RuntimeError('model unavailable')
    monkeypatch.setattr(routes, 'create_speech_services', fail)
    with client.websocket_connect(f'wss://testserver/voice/ws?session_id={sid}') as ws:
        assert ws.receive_json()['type'] == 'session'
        assert ws.receive_json()['type'] == 'status'
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
        assert exc.value.code == 1011
    with gateway.store.conversation(sid):
        assert gateway.app.state.voice_busy is False
    assert client.get('/sessions').status_code == 200


def test_voice_models_reload_once_in_background_after_disconnect(client, monkeypatch):
    login(client)
    calls = []
    monkeypatch.setattr(routes, 'create_speech_services', lambda: calls.append(1) or ())
    with client.websocket_connect('wss://testserver/voice/ws') as ws:
        ws.receive_json()
        assert ws.receive_json()['type'] == 'status'
        assert ws.receive_json()['type'] == 'ready'
    assert gateway.app.state.voice_services is not None
    with client.websocket_connect('wss://testserver/voice/ws') as ws:
        ws.receive_json()
        while ws.receive_json()['type'] != 'ready':
            pass
    # Initial load, then one background reload after each session; never a duplicate.
    assert len(calls) == 3


def test_pipeline_key_error_is_not_reported_as_missing_conversation(client, monkeypatch):
    login(client)
    monkeypatch.setattr(routes, 'create_speech_services', lambda: ())
    async def broken(self):
        raise KeyError('pipeline bug')
    monkeypatch.setattr(routes.WorkerRunner, 'run', broken)
    with client.websocket_connect('wss://testserver/voice/ws') as ws:
        with pytest.raises(WebSocketDisconnect) as exc:
            while True:
                ws.receive_json()
        assert exc.value.code == 1011
