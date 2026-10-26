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


SERVER_TOOLS = [{'type': 'function', 'function': {'name': 'memory_search'}}]
CLIENT_TOOL = {'type': 'function', 'function': {'name': 'calendar_list_events', 'parameters': {'type': 'object'}}}


def test_streaming_forwards_deltas_and_returns_final_text(monkeypatch):
    async def stream(provider, messages, tools=None, tool_choice=None, on_text=None):
        await on_text('Hel')
        await on_text('lo')
        return _reply('Hello')
    monkeypatch.setattr(router, 'stream_complete', stream)
    deltas = []
    async def on_delta(text):
        deltas.append(text)
    result = asyncio.run(router.respond([], 'hi', on_delta=on_delta))
    assert deltas == ['Hel', 'lo'] and result.text == 'Hello'


def test_mid_turn_escalation_stops_deltas(providers, monkeypatch):
    providers()
    seen = []
    async def stream(provider, messages, tools=None, tool_choice=None, on_text=None):
        seen.append((provider.key, on_text))
        return _reply('' if provider.key == 'ollama' else 'Cloud answer')
    monkeypatch.setattr(router, 'stream_complete', stream)
    async def on_delta(text):
        pass
    result = asyncio.run(router.respond([], 'hello', on_delta=on_delta))
    assert result.compute == 'openai'
    assert seen == [('ollama', on_delta), ('openai', None)]


def test_cloud_start_still_streams(providers, monkeypatch):
    providers()
    seen = []
    async def stream(provider, messages, tools=None, tool_choice=None, on_text=None):
        seen.append((provider.key, on_text))
        return _reply('Cloud answer')
    monkeypatch.setattr(router, 'stream_complete', stream)
    async def on_delta(text):
        pass
    asyncio.run(router.respond([], 'escalate this', on_delta=on_delta))
    assert seen == [('openai', on_delta)]


def test_client_tool_calls_go_to_the_client(monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, tools_enabled=True))
    monkeypatch.setattr(router, 'openai_tools', lambda: list(SERVER_TOOLS))
    async def dispatch(name, arguments, ctx):
        raise AssertionError('client tools must not reach the server registry')
    monkeypatch.setattr(router, 'dispatch_call', dispatch)
    call = SimpleNamespace(id='c1', function=SimpleNamespace(name='calendar_list_events', arguments='{}'))
    seen = []
    async def complete(provider, messages, tools=None, tool_choice=None):
        seen.append((list(messages), tools))
        return _reply(None, [call]) if len(seen) == 1 else _reply('Nothing today.')
    monkeypatch.setattr(router, '_complete', complete)
    client_calls = []
    async def call_client(call_id, name, raw):
        client_calls.append((call_id, name, raw))
        return 'No events'
    ctx = SimpleNamespace(used=[])
    result = asyncio.run(router.respond([], 'what is on today?', ctx=ctx, client_tools=[CLIENT_TOOL], call_client=call_client))
    offered_names = [t['function']['name'] for t in seen[0][1]]
    assert offered_names == ['memory_search', 'calendar_list_events']
    assert client_calls == [('c1', 'calendar_list_events', '{}')]
    assert seen[1][0][-1] == {'role': 'tool', 'tool_call_id': 'c1', 'content': 'No events'}
    assert 'calendar_list_events' in result.tools_used


def test_client_tools_are_not_offered_without_a_tool_context(monkeypatch):
    seen_tools = []
    async def complete(provider, messages, tools=None):
        seen_tools.append(tools)
        return _reply('Hi.')
    monkeypatch.setattr(router, '_complete', complete)
    asyncio.run(router.respond([], 'hi', client_tools=[CLIENT_TOOL]))
    assert seen_tools == [None]


def test_context_goes_on_the_latest_user_message(monkeypatch):
    seen = []
    async def complete(provider, messages, tools=None):
        seen.append(messages)
        return _reply('Ready.')
    monkeypatch.setattr(router, '_complete', complete)
    asyncio.run(router.respond([{'role': 'user', 'content': 'Start'}], 'Start', context='Pomodoro idle'))
    assert 'App context: Pomodoro idle' in seen[0][-1]['content']
    assert 'Pomodoro idle' not in seen[0][0]['content']


def test_telemetry_records_each_model_call_and_client_tool_wait(monkeypatch):
    from bt.llm.telemetry import TurnMetrics
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, tools_enabled=True))
    monkeypatch.setattr(router, 'openai_tools', lambda: list(SERVER_TOOLS))
    call = SimpleNamespace(id='c1', function=SimpleNamespace(name='calendar_list_events', arguments='{}'))
    rounds = []
    async def complete(provider, messages, tools=None, tool_choice=None, metrics=None):
        rounds.append(metrics)
        metrics.usage(SimpleNamespace(prompt_tokens=100 * len(rounds), completion_tokens=5))
        return _reply(None, [call]) if len(rounds) == 1 else _reply('Nothing today.')
    monkeypatch.setattr(router, '_complete', complete)
    async def call_client(call_id, name, raw):
        return 'No events'
    published = []
    async def on_update(snapshot):
        published.append(snapshot)
    turn = TurnMetrics('turn', on_update=on_update)
    asyncio.run(router.respond(
        [], 'what is on today?', ctx=SimpleNamespace(used=[]),
        client_tools=[CLIENT_TOOL], call_client=call_client, telemetry=turn,
    ))
    calls = turn.snapshot()['calls']
    assert [c['status'] for c in calls] == ['completed', 'completed']
    assert [c['prompt_tokens'] for c in calls] == [100, 200]
    assert 'tool_wait_ms' in calls[0] and 'tool_wait_ms' not in calls[1]
    assert turn.snapshot()['tool_wait_ms'] >= 0
    assert published, 'live metrics should be published after each call'
    assert 'No events' not in str(turn.snapshot())


@pytest.fixture
def openai_mode(monkeypatch, providers):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, llm_provider='openai', openai_api_key='sk-test'))
    return providers


def test_openai_default_never_touches_ollama(openai_mode):
    calls = openai_mode(openai=[_reply('Cloud answer')])
    result = asyncio.run(router.respond([], 'hello'))
    assert (result.text, result.compute) == ('Cloud answer', 'openai')
    assert [key for key, _ in calls] == ['openai'] and 'ollama' not in router._PROVIDERS


def test_openai_default_streams_deltas(openai_mode, monkeypatch):
    openai_mode()
    seen = []
    async def stream(provider, messages, tools=None, tool_choice=None, on_text=None):
        seen.append(provider.key)
        await on_text('Hi')
        return _reply('Hi')
    monkeypatch.setattr(router, 'stream_complete', stream)
    deltas = []
    async def on_delta(text):
        deltas.append(text)
    result = asyncio.run(router.respond([], 'hello', on_delta=on_delta))
    assert (seen, deltas, result.compute) == (['openai'], ['Hi'], 'openai')


def test_openai_default_dispatches_server_and_client_tools(openai_mode, monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, tools_enabled=True))
    monkeypatch.setattr(router, 'openai_tools', lambda: list(SERVER_TOOLS))
    async def dispatch(name, arguments, ctx):
        return 'memory'
    monkeypatch.setattr(router, 'dispatch_call', dispatch)
    server = SimpleNamespace(id='s1', function=SimpleNamespace(name='memory_search', arguments='{}'))
    client = SimpleNamespace(id='c1', function=SimpleNamespace(name='calendar_list_events', arguments='{}'))
    calls = openai_mode(openai=[_reply(None, [server, client]), _reply('Done.')])
    async def call_client(call_id, name, raw):
        return 'events'
    ctx = SimpleNamespace(used=[])
    result = asyncio.run(router.respond([], 'today?', ctx=ctx, client_tools=[CLIENT_TOOL], call_client=call_client))
    assert (result.text, result.compute) == ('Done.', 'openai')
    assert [key for key, _ in calls] == ['openai', 'openai']
    assert [m['content'] for m in calls[-1][1][-2:]] == ['memory', 'events']


def test_openai_default_errors_propagate_without_local_retry(openai_mode):
    calls = openai_mode(openai=[openai.APIConnectionError(request=_REQUEST)])
    with pytest.raises(openai.APIConnectionError):
        asyncio.run(router.respond([], 'hello'))
    assert [key for key, _ in calls] == ['openai']


def test_openai_default_degenerate_reply_is_not_retried(openai_mode):
    calls = openai_mode(openai=[_reply("I don't know")])
    result = asyncio.run(router.respond([], 'hello'))
    assert result.text == "I don't know" and len(calls) == 1


def test_explicit_local_overrides_openai_default(openai_mode):
    calls = openai_mode(ollama=[_reply('Local answer')])
    result = asyncio.run(router.respond([], 'hello', provider='local'))
    assert (result.compute, [key for key, _ in calls]) == ('ollama', ['ollama'])


def test_missing_openai_key_error_is_clear(providers, monkeypatch):
    monkeypatch.setattr(router, 'CONFIG', replace(router.CONFIG, openai_api_key=None))
    with pytest.raises(RuntimeError, match='^OPENAI_API_KEY is not set$'):
        router._provider('openai')
