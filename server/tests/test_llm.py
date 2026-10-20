import asyncio
from dataclasses import replace

import httpx
import pytest
from openai import AsyncOpenAI

from bt.llm import router

CLOUD_OK = {
    'id': 'x', 'object': 'chat.completion', 'created': 0, 'model': 'm',
    'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'Cloud answer'}, 'finish_reason': 'stop'}],
}


def _client(body, status=200):
    transport = httpx.MockTransport(lambda request: httpx.Response(status, json=body))
    return AsyncOpenAI(base_url='http://test/v1', api_key='k', max_retries=0, http_client=httpx.AsyncClient(transport=transport))


def _install(monkeypatch, local_body, cloud_body=CLOUD_OK, cloud_status=200):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key='test-key'))
    monkeypatch.setattr(router, '_PROVIDERS', {
        'ollama': router.Provider('ollama', 'local', _client(local_body)),
        'openai': router.Provider('openai', 'cloud', _client(cloud_body, cloud_status)),
    })


@pytest.mark.parametrize('body', [
    {},
    {'choices': []},
    {'choices': [{'index': 0, 'message': {'role': 'assistant'}}]},
    {'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': ['bad']}}]},
])
def test_malformed_local_reply_falls_back(body, monkeypatch):
    _install(monkeypatch, body)
    result = asyncio.run(router.respond([{'role': 'user', 'content': 'hello'}], 'hello'))
    assert (result.text, result.compute) == ('Cloud answer', 'openai')


def test_cloud_failure_is_not_retried(monkeypatch):
    _install(monkeypatch, CLOUD_OK, cloud_body={'error': {'message': 'down'}}, cloud_status=500)
    with pytest.raises(Exception):
        asyncio.run(router.respond([], 'escalate'))


def test_local_answer_is_available_without_cloud_key(monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key=''))
    monkeypatch.setattr(router, '_PROVIDERS', {'ollama': router.Provider('ollama', 'local', _client({**CLOUD_OK, 'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'Local answer'}, 'finish_reason': 'stop'}]}))})
    assert asyncio.run(router.respond([], 'hello')).compute == 'ollama'


def test_unknown_provider_is_rejected():
    with pytest.raises(ValueError, match='Unknown provider'):
        asyncio.run(router.respond([], 'hello', provider='mainframe'))
