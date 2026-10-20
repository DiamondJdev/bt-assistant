import asyncio
from types import SimpleNamespace

from bt.library import MemoryStore
from bt.llm import router
from bt.personality import system_prompt


def test_text_path_sends_session_facts(monkeypatch):
    seen = []
    async def complete(provider, messages, tools=None):
        seen.append(messages)
        return SimpleNamespace(content='Local answer', tool_calls=None)
    monkeypatch.setattr(router, '_complete', complete)
    history = [{'role': 'user', 'content': 'What time is it?'}]
    asyncio.run(router.respond(history, 'What time is it?', session_id='s1'))
    system, user = seen[0][0], seen[0][-1]
    assert system['role'] == 'system' and 'Session s1' not in system['content']
    assert user['content'].startswith('What time is it?')
    assert 'Session s1, turn 1.' in user['content']
    assert 'The current date and time is' in user['content']
    assert history[0]['content'] == 'What time is it?'


def test_text_path_recalls_memory_for_a_bare_yes(monkeypatch, tmp_path):
    store = MemoryStore(tmp_path)
    store.write('to-do-list', 'To-do list', 'Fix dinner. Do chemistry homework.')
    monkeypatch.setattr(system_prompt, 'get_memory', lambda: store)
    seen = []
    async def complete(provider, messages, tools=None):
        seen.append(messages)
        return SimpleNamespace(content='Fix dinner, then chemistry.', tool_calls=None)
    monkeypatch.setattr(router, '_complete', complete)
    history = [
        {'role': 'user', 'content': 'Can you read me my to-do list?'},
        {'role': 'assistant', 'content': 'Shall I proceed?'},
        {'role': 'user', 'content': 'Yes.'},
    ]
    asyncio.run(router.respond(history, 'Yes.', session_id='s1'))
    assert 'Do chemistry homework.' in seen[0][-1]['content']


from dataclasses import replace

import httpx
import openai
import pytest

_REQUEST = httpx.Request('POST', 'http://test')


def _reply(content=None, tool_calls=None):
    return SimpleNamespace(content=content, tool_calls=tool_calls)


@pytest.fixture
def providers(monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key='test-key'))
    monkeypatch.setattr(router, '_PROVIDERS', {})
    calls = []
    def install(**replies):
        async def complete(provider, messages, tools=None):
            calls.append((provider.key, list(messages)))
            reply = replies[provider.key].pop(0)
            if isinstance(reply, Exception):
                raise reply
            return reply
        monkeypatch.setattr(router, '_complete', complete)
        return calls
    return install


def test_thinking_is_stripped_from_replies(providers):
    providers(ollama=[_reply('<think>reasoning</think>\nHello, Pilot.')])
    result = asyncio.run(router.respond([], 'hello'))
    assert result.text == 'Hello, Pilot.'


def test_thinking_only_reply_escalates(providers):
    providers(ollama=[_reply('<think>reasoning that never ends')], openai=[_reply('Cloud answer')])
    result = asyncio.run(router.respond([], 'hello'))
    assert (result.text, result.compute) == ('Cloud answer', 'openai')


def test_local_status_error_falls_back_to_cloud(providers):
    missing = openai.NotFoundError('model not found', response=httpx.Response(404, request=_REQUEST), body=None)
    providers(ollama=[missing], openai=[_reply('Cloud answer')])
    result = asyncio.run(router.respond([], 'hello'))
    assert (result.text, result.compute) == ('Cloud answer', 'openai')


def test_cloud_fallback_runs_requested_tools(providers, monkeypatch):
    async def dispatch(name, arguments, ctx):
        return 'You are the Pilot.'
    monkeypatch.setattr(router, 'dispatch_call', dispatch)
    call = SimpleNamespace(id='c1', function=SimpleNamespace(name='memory_search', arguments='{"query": "me"}'))
    calls = providers(
        ollama=[openai.APIConnectionError(request=_REQUEST)],
        openai=[_reply(None, [call]), _reply('You are the Pilot.')],
    )
    ctx = SimpleNamespace(used=[])
    result = asyncio.run(router.respond([], 'who am I?', ctx=ctx))
    assert (result.text, result.compute) == ('You are the Pilot.', 'openai')
    assert calls[-1][1][-1] == {'role': 'tool', 'tool_call_id': 'c1', 'content': 'You are the Pilot.'}


def test_provider_clients_have_bounded_timeout(providers):
    for key in ('ollama', 'openai'):
        client = router._provider(key).client
        assert client.timeout == router.LLM_TIMEOUT_SECS and client.max_retries == 1


def test_tool_budget_final_call_forbids_more_tools(providers, monkeypatch):
    async def dispatch(name, arguments, ctx):
        return 'nothing'
    monkeypatch.setattr(router, 'dispatch_call', dispatch)
    call = SimpleNamespace(id='c1', function=SimpleNamespace(name='memory_search', arguments='{}'))
    seen = []
    async def complete(provider, messages, tools=None, tool_choice=None):
        seen.append((tools, tool_choice))
        return _reply('Done.') if tool_choice == 'none' else _reply(None, [call])
    monkeypatch.setattr(router, '_complete', complete)
    monkeypatch.setattr(router, 'openai_tools', lambda: [{'type': 'function'}])
    result = asyncio.run(router.respond([], 'loop', ctx=SimpleNamespace(used=[])))
    assert result.text == 'Done.'
    assert seen[-1] == ([{'type': 'function'}], 'none')


def test_empty_cloud_reply_raises(providers):
    providers(openai=[_reply('<think>only thoughts</think>')])
    with pytest.raises(ValueError):
        asyncio.run(router.respond([], 'escalate'))
