import asyncio
from dataclasses import replace

import httpx
import pytest

from bt.llm import router


@pytest.mark.parametrize('body', [{}, {'message': {}}, {'message': {'content': None}}, {'message': {'content': ['bad']}}])
def test_malformed_local_reply_falls_back(body, monkeypatch):
    original = httpx.AsyncClient
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key='test-key'))
    monkeypatch.setattr(router.httpx, 'AsyncClient', lambda **kw: original(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=body)), **kw))
    async def cloud(messages):
        return 'Cloud answer'
    monkeypatch.setattr(router, '_call_openai', cloud)
    result = asyncio.run(router.respond([{'role': 'user', 'content': 'hello'}], 'hello'))
    assert result.text == 'Cloud answer'
    assert result.compute == 'openai'


def test_cloud_failure_is_not_retried_recursively(monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key='test-key'))
    async def fail(messages):
        raise httpx.ConnectError('offline')
    monkeypatch.setattr(router, '_call_openai', fail)
    with pytest.raises(httpx.ConnectError):
        asyncio.run(router.respond([], 'escalate'))


def test_local_answer_is_available_without_cloud_key(monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key=''))
    async def local(messages):
        return 'Local answer'
    monkeypatch.setattr(router, '_call_ollama', local)
    assert asyncio.run(router.respond([], 'hello')).compute == 'ollama'
