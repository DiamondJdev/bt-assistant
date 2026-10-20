import asyncio
from dataclasses import replace
from types import SimpleNamespace

from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.services.ollama.llm import OLLamaLLMService
from pipecat.services.openai.llm import OpenAILLMService

from bt.voice import routing


class Stream:
    async def __aiter__(self):
        yield SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content='ok'))])
    async def close(self):
        pass


def _context():
    return LLMContext(messages=[{'role': 'user', 'content': 'hi'}])


def test_voice_refreshes_prompt_each_turn_on_both_services(monkeypatch):
    async def run():
        seen = []
        async def stream(self, context):
            self._compose_system_instruction()  # pipecat may recompose at any point
            seen.append((type(self).__name__, self._settings.system_instruction))
            return Stream()
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(OpenAILLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(routing, 'CONFIG', replace(routing.CONFIG, openai_api_key='test'))
        prompts = iter(['init', 'turn one', 'turn two'])
        monkeypatch.setattr(routing, 'render_system_prompt', lambda **kw: next(prompts))
        service = routing.RoutedLLMService('s1')
        for text in ('hi', 'escalate'):
            out = await service.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': text}]))
            [chunk async for chunk in out]
        assert seen == [('RoutedLLMService', 'turn one'), ('OpenAILLMService', 'turn two')]
        await service.cleanup()
    asyncio.run(run())


def test_voice_prompt_carries_session_and_turn(monkeypatch):
    async def run():
        calls = []
        async def stream(self, context):
            return Stream()
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(routing, 'render_system_prompt', lambda **kw: calls.append(kw) or 'p')
        service = routing.RoutedLLMService('s1')
        out = await service.get_chat_completions(_context())
        [chunk async for chunk in out]
        assert calls[-1] == {'surface': 'voice', 'session_id': 's1', 'turns': 1}
        await service.cleanup()
    asyncio.run(run())
