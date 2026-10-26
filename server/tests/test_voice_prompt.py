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
        assert seen == [('RoutedLLMService', 'turn one' + routing.NO_THINK), ('CloudLLMService', 'turn two')]
        await service.cleanup()
    asyncio.run(run())


def test_voice_request_carries_turn_note_on_latest_user_message(monkeypatch):
    async def run():
        sent, notes = [], []
        async def stream(self, context):
            sent.append(self.build_chat_completion_params({'messages': context.get_messages()})['messages'])
            return Stream()
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(routing, 'turn_note', lambda text, **kw: notes.append((text, kw)) or 'NOTE')
        service = routing.RoutedLLMService('s1')
        context = _context()
        out = await service.get_chat_completions(context)
        [chunk async for chunk in out]
        assert notes == [('hi', {'session_id': 's1', 'turns': 1})]
        assert sent[0][-1]['content'] == 'hi\n\nNOTE'
        assert context.get_messages()[-1]['content'] == 'hi'
        await service.cleanup()
    asyncio.run(run())


def test_voice_recall_searches_the_last_two_user_turns(monkeypatch):
    async def run():
        notes = []
        async def stream(self, context):
            return Stream()
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(routing, 'turn_note', lambda text, **kw: notes.append(text) or 'NOTE')
        service = routing.RoutedLLMService('s1')
        context = LLMContext(messages=[
            {'role': 'user', 'content': 'read my to-do list'},
            {'role': 'assistant', 'content': 'Shall I proceed?'},
            {'role': 'user', 'content': 'Yes.'},
        ])
        out = await service.get_chat_completions(context)
        [chunk async for chunk in out]
        assert notes == ['read my to-do list Yes.']
        await service.cleanup()
    asyncio.run(run())


def test_voice_openai_mode_prompt_has_no_no_think_and_keeps_turn_note(monkeypatch):
    async def run():
        seen = []
        async def stream(self, context):
            self._compose_system_instruction()
            seen.append((type(self).__name__, self._settings.system_instruction, self.turn_note))
            return Stream()
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(OpenAILLMService, 'get_chat_completions', stream)
        monkeypatch.setattr(routing, 'CONFIG', replace(routing.CONFIG, llm_provider='openai', openai_api_key='test'))
        monkeypatch.setattr(routing, 'render_system_prompt', lambda **kw: 'prompt')
        monkeypatch.setattr(routing, 'turn_note', lambda text, **kw: 'NOTE')
        service = routing.RoutedLLMService('s1')
        out = await service.get_chat_completions(_context())
        [chunk async for chunk in out]
        assert seen == [('CloudLLMService', 'prompt', 'NOTE')]
        await service.cleanup()
    asyncio.run(run())
