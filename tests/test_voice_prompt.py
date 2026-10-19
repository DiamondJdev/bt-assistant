import asyncio

from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.services.ollama.llm import OLLamaLLMService

from bt.voice import pipeline


def test_voice_refreshes_system_prompt_each_turn(monkeypatch):
    async def run():
        seen = []
        async def stream(self, context):
            seen.append(self._settings.system_instruction)
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        prompts = iter(['init', 'first', 'second'])
        monkeypatch.setattr(pipeline, 'render_system_prompt', lambda **kw: next(prompts))
        llm = pipeline.FreshPromptLLMService('s1')
        for _ in range(2):
            await llm.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hi'}]))
        assert seen == ['first', 'second']
        await llm.cleanup()
    asyncio.run(run())


def test_voice_prompt_survives_pipecat_recompose(monkeypatch):
    async def run():
        async def stream(self, context):
            self._compose_system_instruction()
            seen.append(self._settings.system_instruction)
        seen = []
        monkeypatch.setattr(OLLamaLLMService, 'get_chat_completions', stream)
        prompts = iter(['init', 'fresh'])
        monkeypatch.setattr(pipeline, 'render_system_prompt', lambda **kw: next(prompts))
        llm = pipeline.FreshPromptLLMService('s1')
        await llm.get_chat_completions(LLMContext(messages=[{'role': 'user', 'content': 'hi'}]))
        assert seen == ['fresh']
        await llm.cleanup()
    asyncio.run(run())
