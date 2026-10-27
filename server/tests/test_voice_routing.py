import asyncio
from dataclasses import replace
from types import SimpleNamespace

import pytest
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.services.ollama.llm import OLLamaLLMService
from pipecat.services.openai.llm import OpenAILLMService

from bt.voice import routing


class Stream:
    def __init__(self, texts, error=None):
        self.texts, self.error, self.closed = texts, error, False
    async def __aiter__(self):
        for text in self.texts:
            yield SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=text))])
        if self.error:
            raise self.error
    async def close(self):
        self.closed = True


@pytest.mark.parametrize('model,has_tools,expected', [
    ('gpt-5.6-luna', True, 'none'),
    ('gpt-5.6-luna', False, None),
    ('gpt-4.1', True, None),
])
def test_voice_luna_tool_requests_disable_reasoning(model, has_tools, expected):
    async def run():
        service = routing.CloudLLMService(api_key='test', settings=OpenAILLMService.Settings(model=model))
        tools = [{'type': 'function', 'function': {'name': 'check'}}] if has_tools else []
        params = service.build_chat_completion_params({'messages': [], 'tools': tools})
        assert params.get('reasoning_effort') == expected
        if expected is None:
            assert 'reasoning_effort' not in params
        await service.cleanup()
    asyncio.run(run())


@pytest.mark.parametrize('prompt,broken,want', [('hello',False,'local'),('escalate',False,'cloud'),('hello',True,'cloud')])
def test_voice_stream_routes_and_closes_providers(prompt, broken, want, monkeypatch):
    async def run():
        local = Stream([] if broken else ['local'], RuntimeError('offline') if broken else None)
        cloud = Stream(['cloud'])
        async def local_stream(self, context):
            return local
        async def cloud_stream(self, context):
            return cloud
        monkeypatch.setattr(OLLamaLLMService,'get_chat_completions',local_stream)
        monkeypatch.setattr(OpenAILLMService,'get_chat_completions',cloud_stream)
        monkeypatch.setattr(routing,'CONFIG',replace(routing.CONFIG,openai_api_key='test'))
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role':'user','content':prompt}]))
        chunks = [chunk.choices[0].delta.content async for chunk in stream]
        assert chunks == [want]
        assert service.compute == ('openai' if want == 'cloud' else 'ollama')
        assert (cloud if want == 'cloud' else local).closed
        if broken:
            assert local.closed
        await service.cleanup()
    asyncio.run(run())


def test_voice_does_not_repeat_answer_after_partial_stream_failure(monkeypatch):
    async def run():
        local = Stream(['partial'], RuntimeError('disconnected'))
        async def local_stream(self, context):
            return local
        monkeypatch.setattr(OLLamaLLMService,'get_chat_completions',local_stream)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role':'user','content':'hello'}]))
        assert (await anext(stream)).choices[0].delta.content == 'partial'
        with pytest.raises(RuntimeError, match='disconnected'):
            await anext(stream)
        assert local.closed
        await service.cleanup()
    asyncio.run(run())


class SlowStream(Stream):
    def __init__(self, texts, delay):
        super().__init__(texts)
        self.delay = delay
    async def __aiter__(self):
        for text in self.texts:
            await asyncio.sleep(self.delay)
            yield SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=text))])


def test_voice_timeout_bounds_each_chunk_not_whole_answer(monkeypatch):
    async def run():
        local = SlowStream(['a', 'b', 'c'], 0.02)
        async def local_stream(self, context):
            return local
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
        monkeypatch.setattr(routing, 'CHUNK_TIMEOUT', 0.1)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        chunks = []
        async for chunk in stream:
            chunks.append(chunk.choices[0].delta.content)
            await asyncio.sleep(0.05)  # slow consumer, e.g. TTS backpressure
        assert chunks == ['a', 'b', 'c']
        await service.cleanup()
    asyncio.run(run())


def test_voice_stalled_local_model_falls_back_to_cloud(monkeypatch):
    async def run():
        local = SlowStream(['late'], 1)
        cloud = Stream(['cloud'])
        async def local_stream(self, context):
            return local
        async def cloud_stream(self, context):
            return cloud
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
        monkeypatch.setattr(OpenAILLMService, 'get_chat_completions', cloud_stream)
        monkeypatch.setattr(routing, 'CONFIG', replace(routing.CONFIG, openai_api_key='test'))
        monkeypatch.setattr(routing, 'CHUNK_TIMEOUT', 0.05)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        assert [chunk.choices[0].delta.content async for chunk in stream] == ['cloud']
        await service.cleanup()
    asyncio.run(run())


def test_voice_history_trim_starts_on_user_turn(monkeypatch):
    async def run():
        async def local_stream(self, context):
            return Stream(['ok'])
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
        roles = ['user', 'assistant'] * 30 + ['user']
        context = LLMContext(messages=[{'role': r, 'content': f'{i} ' + 'x' * 1000} for i, r in enumerate(roles)])
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(context)
        [chunk async for chunk in stream]
        messages = context.get_messages()
        assert sum(len(m['content']) for m in messages) <= routing.MAX_HISTORY_CHARS
        assert messages[0]['role'] == 'user'
        assert messages[-1]['content'].startswith('60 ')
        await service.cleanup()
    asyncio.run(run())


def test_voice_history_trim_keeps_oversized_current_turn():
    big = 'x' * routing.MAX_HISTORY_CHARS
    context = LLMContext(messages=[
        {'role': 'user', 'content': 'old'}, {'role': 'assistant', 'content': 'old'},
        {'role': 'user', 'content': 'now'}, {'role': 'tool', 'content': big},
    ])
    routing._trim(context, routing.MAX_HISTORY_CHARS)
    assert [m['content'] for m in context.get_messages()] == ['now', big]


def test_voice_tool_call_only_reply_is_not_empty(monkeypatch):
    async def run():
        call = SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=None, tool_calls=[object()]), finish_reason='tool_calls')])
        class ToolStream(Stream):
            async def __aiter__(self):
                yield call
        local = ToolStream([])
        async def local_stream(self, context):
            return local
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        assert [chunk async for chunk in stream] == [call]
        await service.cleanup()
    asyncio.run(run())


def _openai_mode(monkeypatch, cloud):
    local_calls = []
    async def local_stream(self, context):
        local_calls.append(context)
        return Stream(['local'])
    async def cloud_stream(self, context):
        return cloud
    monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
    monkeypatch.setattr(OpenAILLMService, 'get_chat_completions', cloud_stream)
    monkeypatch.setattr(routing, 'CONFIG', replace(routing.CONFIG, llm_provider='openai', openai_api_key='test'))
    return local_calls


def test_voice_openai_mode_starts_on_cloud_without_ollama(monkeypatch):
    async def run():
        cloud = Stream(['cloud'])
        local_calls = _openai_mode(monkeypatch, cloud)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        assert [chunk.choices[0].delta.content async for chunk in stream] == ['cloud']
        assert local_calls == []
        assert service.compute == 'openai'
        assert cloud.closed
        await service.cleanup()
    asyncio.run(run())


def test_voice_openai_mode_propagates_partial_cloud_errors(monkeypatch):
    async def run():
        cloud = Stream(['partial'], RuntimeError('cloud down'))
        local_calls = _openai_mode(monkeypatch, cloud)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        seen = []
        with pytest.raises(RuntimeError, match='cloud down'):
            async for chunk in stream:
                seen.append(chunk.choices[0].delta.content)
        assert seen == ['partial']
        assert local_calls == []
        assert service.compute == 'openai'
        assert cloud.closed
        await service.cleanup()
    asyncio.run(run())


@pytest.mark.parametrize('failure', [None, RuntimeError('cloud down')])
def test_voice_cloud_failure_falls_back_with_local_history_budget(monkeypatch, failure):
    async def run():
        cloud = Stream([], failure)
        local_calls = _openai_mode(monkeypatch, cloud)
        service = routing.RoutedLLMService()
        messages = [{'role': 'user' if i % 2 == 0 else 'assistant', 'content': 'x' * 1000} for i in range(40)]
        stream = await service.get_chat_completions(LLMContext(messages=messages))
        assert [chunk.choices[0].delta.content async for chunk in stream] == ['local']
        assert service.compute == 'ollama' and cloud.closed
        assert len(local_calls) == 1
        assert len(local_calls[0].get_messages()) < 40
        await service.cleanup()
    asyncio.run(run())


def test_voice_fallback_failure_does_not_cycle(monkeypatch):
    async def run():
        cloud = Stream([], RuntimeError('cloud down'))
        _openai_mode(monkeypatch, cloud)
        local = Stream([], RuntimeError('local down'))
        async def local_stream(self, context):
            return local
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', local_stream)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        with pytest.raises(RuntimeError, match='local down'):
            await anext(stream)
        assert cloud.closed and local.closed
        await service.cleanup()
    asyncio.run(run())


def test_voice_does_not_retry_after_cloud_tool_output(monkeypatch):
    async def run():
        call = SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=None, tool_calls=[object()]))])
        class ToolStream(Stream):
            async def __aiter__(self):
                yield call
                raise RuntimeError('cloud down')
        cloud = ToolStream([])
        local_calls = _openai_mode(monkeypatch, cloud)
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        assert await anext(stream) == call
        with pytest.raises(RuntimeError, match='cloud down'):
            await anext(stream)
        assert not local_calls and cloud.closed
        await service.cleanup()
    asyncio.run(run())


def test_voice_openai_mode_tool_call_only_reply_is_not_empty(monkeypatch):
    async def run():
        call = SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=None, tool_calls=[object()]), finish_reason='tool_calls')])
        class ToolStream(Stream):
            async def __aiter__(self):
                yield call
        _openai_mode(monkeypatch, ToolStream([]))
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        assert [chunk async for chunk in stream] == [call]
        assert service.compute == 'openai'
        await service.cleanup()
    asyncio.run(run())


def test_voice_openai_mode_without_key_says_so(monkeypatch):
    async def run():
        monkeypatch.setattr(routing, 'CONFIG', replace(routing.CONFIG, llm_provider='openai', openai_api_key=''))
        service = routing.RoutedLLMService()
        stream = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hello'}]))
        with pytest.raises(RuntimeError, match='OpenAI requires OPENAI_API_KEY'):
            await anext(stream)
        await service.cleanup()
    asyncio.run(run())


def test_voice_history_budget_follows_the_provider(monkeypatch):
    messages = [{'role': 'user' if i % 2 == 0 else 'assistant', 'content': 'x' * 1000} for i in range(40)]
    small = LLMContext(messages=list(messages))
    routing._trim(small, routing.MAX_HISTORY_CHARS)
    assert len(small.get_messages()) < 40
    large = LLMContext(messages=list(messages))
    routing._trim(large, routing.CLOUD_HISTORY_CHARS)
    assert len(large.get_messages()) == 40
