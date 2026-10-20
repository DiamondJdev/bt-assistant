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
    routing._trim(context)
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
