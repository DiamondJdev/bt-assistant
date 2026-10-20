import asyncio
import threading

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from bt.gateway import chat_ws, gateway
from bt.llm.router import LLMResponse
from bt.transcript.store import TranscriptStore


@pytest.fixture
def client(monkeypatch):
    db = TranscriptStore(':memory:')
    monkeypatch.setattr(gateway, 'store', db)
    monkeypatch.setattr(chat_ws, 'store', db)
    with TestClient(gateway.app, base_url='https://testserver') as c:
        yield c


def _install(monkeypatch, fake):
    monkeypatch.setattr(chat_ws, 'respond', fake)


async def _hello(messages, text, **kw):
    await kw['on_delta']('Hel')
    await kw['on_delta']('lo')
    return LLMResponse('Hello', 'ollama')


def _roles(client, sid):
    return [t['role'] for t in client.get('/history', params={'session_id': sid}).json()]


def test_new_socket_announces_a_session_and_streams_a_turn(client, monkeypatch):
    _install(monkeypatch, _hello)
    with client.websocket_connect('/chat/ws') as ws:
        session = ws.receive_json()
        assert session['type'] == 'session'
        sid = session['session_id']
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json() == {'type': 'delta', 'text': 'Hel'}
        assert ws.receive_json() == {'type': 'delta', 'text': 'lo'}
        done = ws.receive_json()
    assert done == {'type': 'done', 'text': 'Hello', 'compute': 'ollama', 'tools_used': []}
    assert _roles(client, sid) == ['user', 'bt']


def test_existing_session_is_continued(client, monkeypatch):
    _install(monkeypatch, _hello)
    sid = client.post('/sessions').json()['session_id']
    with client.websocket_connect(f'/chat/ws?session_id={sid}') as ws:
        assert ws.receive_json() == {'type': 'session', 'session_id': sid}


def test_context_is_stored_and_passed_to_the_router(client, monkeypatch):
    seen = {}
    async def fake(messages, text, **kw):
        seen['context'] = kw['context']
        return LLMResponse('Ready.', 'ollama')
    _install(monkeypatch, fake)
    with client.websocket_connect('/chat/ws') as ws:
        sid = ws.receive_json()['session_id']
        ws.send_json({'type': 'message', 'text': 'Start', 'context': 'Pomodoro idle'})
        assert ws.receive_json()['type'] == 'done'
    history = client.get('/history', params={'session_id': sid}).json()
    assert seen['context'] == 'Pomodoro idle' and history[0]['context'] == 'Pomodoro idle'
    assert history[1]['context'] is None


def test_unknown_session_is_reported_and_closed(client):
    with client.websocket_connect('/chat/ws?session_id=missing') as ws:
        assert ws.receive_json() == {'type': 'error', 'message': 'Conversation not found'}
        with pytest.raises(WebSocketDisconnect) as closed:
            ws.receive_json()
    assert closed.value.code == 1008


def test_busy_conversation_reports_and_socket_stays_usable(client, monkeypatch):
    _install(monkeypatch, _hello)
    with client.websocket_connect('/chat/ws') as ws:
        sid = ws.receive_json()['session_id']
        with gateway.store.conversation(sid):
            ws.send_json({'type': 'message', 'text': 'Hi'})
            assert ws.receive_json() == {
                'type': 'error',
                'message': 'Conversation is busy. Disconnect voice or wait for the current reply.',
            }
        ws.send_json({'type': 'message', 'text': 'Hi'})
        frames = [ws.receive_json() for _ in range(3)]
    assert frames[-1]['type'] == 'done'
    assert _roles(client, sid) == ['user', 'bt']


def test_phone_post_during_socket_turn_gets_409(client, monkeypatch):
    release = threading.Event()
    async def slow(messages, text, **kw):
        await kw['on_delta']('Thinking')
        await asyncio.to_thread(release.wait, 5)
        return LLMResponse('Done.', 'ollama')
    _install(monkeypatch, slow)
    async def phone_reply(messages, text, **kw):
        return LLMResponse('Phone reply', 'ollama')
    monkeypatch.setattr(gateway, 'respond', phone_reply)
    with client.websocket_connect('/chat/ws') as ws:
        sid = ws.receive_json()['session_id']
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json() == {'type': 'delta', 'text': 'Thinking'}
        ws.send_json({'type': 'message', 'text': 'Again'})
        assert ws.receive_json() == {'type': 'error', 'message': 'Wait for the current reply.'}
        assert client.post('/chat', json={'text': 'from phone', 'session_id': sid}).status_code == 409
        release.set()
        assert ws.receive_json()['text'] == 'Done.'
        ws.send_json({'type': 'message', 'text': 'Next'})
        frames = [ws.receive_json() for _ in range(2)]
    assert frames[-1] == {'type': 'done', 'text': 'Done.', 'compute': 'ollama', 'tools_used': []}


def test_bad_frames_and_blank_text_return_errors(client, monkeypatch):
    _install(monkeypatch, _hello)
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        ws.send_text('not json')
        assert ws.receive_json() == {'type': 'error', 'message': 'Unrecognized message.'}
        ws.send_json({'type': 'nope'})
        assert ws.receive_json() == {'type': 'error', 'message': 'Unrecognized message.'}
        ws.send_json({'text': 'no type'})
        assert ws.receive_json() == {'type': 'error', 'message': 'Unrecognized message.'}
        ws.send_bytes(b'binary')
        assert ws.receive_json() == {'type': 'error', 'message': 'Unrecognized message.'}
        ws.send_json({'type': 'message', 'text': '   '})
        assert ws.receive_json() == {'type': 'error', 'message': 'Enter a message'}
        ws.send_json({'type': 'message', 'text': 'Hi', 'context': 'x' * 4001})
        assert ws.receive_json() == {'type': 'error', 'message': 'Context is too long.'}
        ws.send_json({'type': 'message', 'text': 'Hi', 'context': 'x' * 4000})
        assert [ws.receive_json()['type'] for _ in range(3)] == ['delta', 'delta', 'done']


def test_failed_turn_reports_and_stores_no_reply(client, monkeypatch):
    async def fail(messages, text, **kw):
        raise RuntimeError('sensitive provider detail')
    _install(monkeypatch, fail)
    with client.websocket_connect('/chat/ws') as ws:
        sid = ws.receive_json()['session_id']
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json() == {'type': 'error', 'message': 'Response failed. Try again.'}
    assert _roles(client, sid) == ['user']


def test_hello_rejects_bad_and_colliding_tool_names(client, monkeypatch):
    seen = []
    async def fake(messages, text, **kw):
        seen.append(kw['client_tools'])
        return LLMResponse('Hi.', 'ollama')
    _install(monkeypatch, fake)
    tool = {'description': 'List events', 'parameters': {'type': 'object', 'properties': {}}}
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        for tools in (
            [{**tool, 'name': 'calendar.list'}],
            [{**tool, 'name': 'memory_search'}],
            [{**tool, 'name': 'a'}, {**tool, 'name': 'a'}],
            'not a list',
        ):
            ws.send_json({'type': 'hello', 'tools': tools})
            error = ws.receive_json()
            assert error['type'] == 'error' and error['message'].startswith('Tools were rejected: ')
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json()['type'] == 'done'
        ws.send_json({'type': 'hello', 'tools': [{**tool, 'name': 'late'}]})
        assert ws.receive_json()['message'].startswith('Tools were rejected: ')
    assert seen == [None]


def test_hello_tools_reach_the_router(client, monkeypatch):
    seen = []
    async def fake(messages, text, **kw):
        seen.append((kw['client_tools'], kw['ctx'] is not None))
        return LLMResponse('Hi.', 'ollama')
    _install(monkeypatch, fake)
    tool = {'name': 'calendar_list_events', 'description': 'List events', 'parameters': {'type': 'object'}}
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'hello', 'tools': [tool]})
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json()['type'] == 'done'
    assert seen == [([{'type': 'function', 'function': tool}], True)]
