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


def login(client):
    assert client.post('/auth/login', json={'token': 'test-access-token'}).status_code == 200


def test_private_routes_require_token_and_cookie_is_http_only(client):
    for path in ['/history?session_id=missing', '/sessions', '/config', '/ready']:
        assert client.get(path).status_code == 401
    assert client.post('/chat', json={'text': 'hello'}).status_code == 401
    assert client.post('/auth/login', json={'token': 'wrong'}).status_code == 401
    response = client.post('/auth/login', json={'token': 'test-access-token'})
    cookie = response.headers['set-cookie'].lower()
    assert 'httponly' in cookie and 'secure' in cookie and 'samesite=strict' in cookie
    sessions = client.get('/sessions')
    assert sessions.json() == []
    assert sessions.headers['cache-control'] == 'no-store'
    client.post('/auth/logout')
    assert client.get('/sessions').status_code == 401
    assert client.get('/sessions', headers={'Authorization': 'Bearer test-access-token'}).status_code == 200


def test_cross_origin_cookie_requests_are_rejected(client):
    login(client)
    assert client.post('/sessions', headers={'Origin': 'https://other.example'}).status_code == 403
    assert client.post('/auth/login', json={'token': 'test-access-token'}, headers={'Origin': 'https://other.example'}).status_code == 403


def test_same_host_origin_is_accepted_behind_tls_proxy(client):
    bearer = {'Authorization': 'Bearer test-access-token'}
    # Serve terminates TLS, so BT may see plain http for an https page.
    assert client.post('http://testserver/sessions', headers={**bearer, 'Origin': 'https://testserver'}).status_code == 200
    proxied = {**bearer, 'Host': '127.0.0.1:8080', 'X-Forwarded-Host': 'bt.example.ts.net', 'Origin': 'https://bt.example.ts.net'}
    assert client.post('/sessions', headers=proxied).status_code == 200
    proxied['Origin'] = 'https://other.example'
    assert client.post('/sessions', headers=proxied).status_code == 403


def test_sessions_chat_validation_and_unknown_ids(client, monkeypatch):
    login(client)
    async def reply(messages, text):
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
    login(client)
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
    login(client)
    async def tags(request):
        return httpx.Response(200, json={'models': [{'name': 'qwen3:8b'}]})
    original = httpx.AsyncClient
    monkeypatch.setattr(gateway.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(tags), **kw))
    assert client.get('/ready').status_code == 200
    async def no_models(request):
        return httpx.Response(200, json={'models': []})
    monkeypatch.setattr(gateway.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(no_models), **kw))
    assert client.get('/ready').status_code == 503
