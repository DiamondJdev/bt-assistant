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


def test_voice_holds_conversation_lease_and_limits_connections(client):
    login(client)
    sid = client.post('/sessions').json()['session_id']
    gateway.app.state.voice_services = ()
    with client.websocket_connect(f'wss://testserver/voice/ws?session_id={sid}') as ws:
        assert ws.receive_json()['sessionId'] == sid
        assert ws.receive_json()['type'] == 'ready'
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
