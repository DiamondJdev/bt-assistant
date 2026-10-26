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


def test_opt_in_diagnostics_correlate_done_and_live_metrics(client, monkeypatch):
    turn_id = '7533469b-893b-4c9b-9666-e25698b2714b'
    async def fake(messages, text, **kw):
        await kw['telemetry'].publish()
        return LLMResponse('Hello', 'ollama')
    _install(monkeypatch, fake)
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'message', 'text': 'Hi', 'diagnostics': True, 'turn_id': turn_id.upper()})
        live = ws.receive_json()
        assert live['type'] == 'metrics'
        done = ws.receive_json()
    assert live['type'] == 'metrics' and live['turn_id'] == turn_id
    assert done['turn_id'] == turn_id
    assert done['metrics']['history_turns'] == 1
    assert done['metrics']['context_chars'] == 0
    assert done['metrics']['calls'] == []


def test_diagnostics_generate_id_and_correlate_private_errors(client, monkeypatch, caplog):
    async def fake(*args, **kwargs):
        raise RuntimeError('secret prompt and credential')
    _install(monkeypatch, fake)
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'message', 'text': 'Hi', 'diagnostics': True})
        error = ws.receive_json()
    from uuid import UUID
    assert UUID(error['turn_id'])
    assert error['metrics']['status'] == 'error'
    assert error['turn_id'] in caplog.text
    assert 'secret prompt and credential' not in caplog.text


@pytest.mark.parametrize('turn_id', ['x' * 100, 'not-a-uuid', 123])
def test_invalid_turn_ids_are_rejected(client, monkeypatch, turn_id):
    _install(monkeypatch, _hello)
    with client.websocket_connect('/chat/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'message', 'text': 'Hi', 'turn_id': turn_id})
        assert ws.receive_json()['type'] == 'error'


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


TOOL = {'name': 'calendar_list_events', 'description': 'List events', 'parameters': {'type': 'object'}}


def _tool_turn(monkeypatch, raw='{"day": "today"}'):
    async def fake(messages, text, **kw):
        content = await kw['call_client']('c1', 'calendar_list_events', raw)
        return LLMResponse(content, 'ollama', ('calendar_list_events',))
    _install(monkeypatch, fake)


def _start(ws):
    ws.receive_json()
    ws.send_json({'type': 'hello', 'tools': [TOOL]})
    ws.send_json({'type': 'message', 'text': 'What is on today?'})


def test_client_tool_round_trip(client, monkeypatch):
    _tool_turn(monkeypatch)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        tool_call = ws.receive_json()
        assert tool_call == {'type': 'tool_call', 'id': 'c1', 'name': 'calendar_list_events', 'args': {'day': 'today'}}
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': True, 'content': 'No events'})
        done = ws.receive_json()
    assert done['text'] == 'No events'
    assert done['tools_used'] == ['calendar_list_events']


def test_invalid_tool_arguments_reach_the_client_as_an_empty_object(client, monkeypatch):
    _tool_turn(monkeypatch, raw='{not json')
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        assert ws.receive_json()['args'] == {}
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': True, 'content': 'ok'})
        assert ws.receive_json()['type'] == 'done'


def test_failed_client_tool_is_reported_to_the_model(client, monkeypatch):
    _tool_turn(monkeypatch)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        ws.receive_json()
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': False, 'content': 'Calendar access is off'})
        done = ws.receive_json()
    assert done['text'] == 'calendar_list_events failed: Calendar access is off'


def test_unanswered_client_tool_times_out(client, monkeypatch):
    monkeypatch.setattr(chat_ws, 'CLIENT_TOOL_TIMEOUT_SECS', 0.05)
    _tool_turn(monkeypatch)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        assert ws.receive_json()['type'] == 'tool_call'
        assert ws.receive_json() == {'type': 'tool_cancelled', 'id': 'c1'}
        done = ws.receive_json()
        ws.send_json({'type': 'tool_approval', 'id': 'c1'})
        assert ws.receive_json() == {'type': 'tool_cancelled', 'id': 'c1'}
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': True, 'content': 'too late'})
        ws.send_json({'type': 'message', 'text': 'still there?'})
        assert ws.receive_json()['type'] == 'tool_call'
    assert done['text'] == 'The app did not answer calendar_list_events in time.'


def test_live_client_tool_approval_is_acknowledged(client, monkeypatch):
    _tool_turn(monkeypatch)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        assert ws.receive_json()['type'] == 'tool_call'
        ws.send_json({'type': 'tool_approval', 'id': 'other'})
        assert ws.receive_json() == {'type': 'tool_cancelled', 'id': 'other'}
        ws.send_json({'type': 'tool_approval', 'id': 'c1'})
        assert ws.receive_json() == {'type': 'tool_approved', 'id': 'c1'}
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': True, 'content': 'Approved'})
        assert ws.receive_json()['text'] == 'Approved'


def test_late_approval_is_rejected_while_followup_is_streaming(client, monkeypatch):
    monkeypatch.setattr(chat_ws, 'CLIENT_TOOL_TIMEOUT_SECS', 0.05)
    resume = threading.Event()
    async def fake(messages, text, **kw):
        content = await kw['call_client']('c1', 'calendar_list_events', '{}')
        await kw['on_delta']('Continuing after timeout')
        await asyncio.to_thread(resume.wait, 2)
        return LLMResponse(content, 'ollama')
    _install(monkeypatch, fake)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        assert ws.receive_json()['type'] == 'tool_call'
        assert ws.receive_json() == {'type': 'tool_cancelled', 'id': 'c1'}
        assert ws.receive_json()['type'] == 'delta'
        ws.send_json({'type': 'tool_approval', 'id': 'c1'})
        assert ws.receive_json() == {'type': 'tool_cancelled', 'id': 'c1'}
        resume.set()
        assert ws.receive_json()['type'] == 'done'


def test_unknown_tool_result_is_ignored(client, monkeypatch):
    _tool_turn(monkeypatch)
    with client.websocket_connect('/chat/ws') as ws:
        _start(ws)
        ws.receive_json()
        ws.send_json({'type': 'tool_result', 'id': 'other', 'ok': True, 'content': 'wrong'})
        ws.send_json({'type': 'tool_result', 'id': 'c1', 'ok': True, 'content': 'No events'})
        assert ws.receive_json()['text'] == 'No events'


def test_disconnect_mid_turn_cancels_and_stores_no_reply(client, monkeypatch):
    cancelled = threading.Event()
    async def blocks(messages, text, **kw):
        await kw['on_delta']('Working')
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            cancelled.set()
            raise
        return LLMResponse('never', 'ollama')
    _install(monkeypatch, blocks)
    with client.websocket_connect('/chat/ws') as ws:
        sid = ws.receive_json()['session_id']
        ws.send_json({'type': 'message', 'text': 'Hi'})
        assert ws.receive_json()['type'] == 'delta'
    assert cancelled.wait(2)
    assert _roles(client, sid) == ['user']
    with gateway.store.conversation(sid):
        pass  # the lease was released
