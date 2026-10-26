import asyncio
from dataclasses import replace

import httpx
import pytest
from fastapi.testclient import TestClient

from bt.gateway import gateway
from bt.llm.router import LLMResponse
from bt.transcript.store import TranscriptStore


@pytest.fixture
def client(monkeypatch):
    db = TranscriptStore(':memory:')
    monkeypatch.setattr(gateway, 'store', db)
    with TestClient(gateway.app, base_url='https://testserver') as c:
        yield c


def test_routes_are_open_without_credentials(client):
    assert client.get('/sessions').json() == []
    assert client.get('/sessions').headers['cache-control'] == 'no-store'
    assert client.post('/sessions').status_code == 200
    assert client.post('/auth/login', json={'token': 'x'}).status_code == 404


def test_cross_origin_requests_are_rejected(client):
    # Open access must not let websites the owner visits drive BT.
    assert client.post('/sessions', headers={'Origin': 'https://other.example'}).status_code == 403
    assert client.get('/sessions', headers={'Origin': 'https://other.example'}).status_code == 403


def test_same_host_origin_is_accepted_behind_tls_proxy(client):
    # Serve terminates TLS, so BT may see plain http for an https page.
    assert client.post('http://testserver/sessions', headers={'Origin': 'https://testserver'}).status_code == 200
    proxied = {'Host': '127.0.0.1:8080', 'X-Forwarded-Host': 'bt.example.ts.net', 'Origin': 'https://bt.example.ts.net'}
    assert client.post('/sessions', headers=proxied).status_code == 200
    proxied['Origin'] = 'https://other.example'
    assert client.post('/sessions', headers=proxied).status_code == 403


def test_sessions_chat_validation_and_unknown_ids(client, monkeypatch):
    async def reply(messages, text, **kw):
        return LLMResponse('Hello pilot', 'ollama')
    monkeypatch.setattr(gateway, 'respond', reply)
    assert client.post('/chat', json={'text': '   '}).status_code == 422
    assert client.post('/chat', json={'text': 'x' * 16001}).status_code == 422
    assert client.post('/chat', json={'text': 'hi', 'session_id': 'missing'}).status_code == 404
    assert client.get('/history?session_id=missing').status_code == 404
    sid = client.post('/sessions').json()['session_id']
    with gateway.store.conversation(sid):
        assert client.post('/chat', json={'text': 'hi', 'session_id': sid}).status_code == 409
    response = client.post('/chat', json={'text': 'hi', 'session_id': sid})
    assert response.status_code == 200
    assert [t['text'] for t in client.get('/history', params={'session_id': sid}).json()] == ['hi', 'Hello pilot']
    assert client.get('/sessions').json()[0]['id'] == sid


def test_failed_chat_preserves_session_and_can_be_retried(client, monkeypatch):
    async def fail(*args):
        raise RuntimeError('sensitive provider detail')
    monkeypatch.setattr(gateway, 'respond', fail)
    response = client.post('/chat', json={'text': 'hi'})
    assert response.status_code == 502
    assert 'sensitive' not in response.text
    sid = response.json()['detail']['session_id']
    with gateway.store.conversation(sid):
        assert gateway.store.history(sid)[0].text == 'hi'


def test_readiness_checks_model_and_reports_dependency_failure(client, monkeypatch):
    async def tags(request):
        return httpx.Response(200, json={'models': [{'name': 'qwen3:8b'}]})
    original = httpx.AsyncClient
    monkeypatch.setattr(gateway.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(tags), **kw))
    assert client.get('/ready').status_code == 200
    async def no_models(request):
        return httpx.Response(200, json={'models': []})
    monkeypatch.setattr(gateway.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(no_models), **kw))
    assert client.get('/ready').status_code == 503
    assert client.get('/ready').json()['reason'] == 'Model qwen3:8b is not installed'
    async def down(request):
        raise httpx.ConnectError('refused')
    monkeypatch.setattr(gateway.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(down), **kw))
    assert client.get('/ready').json()['reason'] == 'Ollama is not reachable'


def test_config_reports_model_for_status_display(client):
    assert client.get('/config').json()['model'] == gateway.CONFIG.ollama_model


def test_memories_lists_the_index_without_bodies(client, monkeypatch, tmp_path):
    from bt.library import MemoryStore
    memories = MemoryStore(tmp_path)
    memories.write('lab-room', 'The CHEM lab is in room 210', 'Room 210, second floor.', type='user')
    monkeypatch.setattr(gateway, 'get_memory', lambda: memories)

    [entry] = client.get('/memories').json()

    assert entry['name'] == 'lab-room'
    assert entry['description'] == 'The CHEM lab is in room 210'
    assert entry['type'] == 'user'
    assert entry['updated']
    assert 'body' not in entry
