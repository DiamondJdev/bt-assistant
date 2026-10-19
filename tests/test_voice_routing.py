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
