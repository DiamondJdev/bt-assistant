import asyncio
from types import SimpleNamespace

from bt.llm import router


def test_text_path_sends_session_facts(monkeypatch):
    seen = []
    async def complete(provider, messages, tools=None):
        seen.append(messages)
        return SimpleNamespace(content='Local answer', tool_calls=None)
    monkeypatch.setattr(router, '_complete', complete)
    history = [{'role': 'user', 'content': 'What time is it?'}]
    asyncio.run(router.respond(history, 'What time is it?', session_id='s1'))
    system = seen[0][0]
    assert system['role'] == 'system'
    assert 'Session s1, turn 1.' in system['content']
    assert 'The current date and time is' in system['content']
