import asyncio
from pathlib import Path

from bt.voice import pipeline, routing


def test_piper_cache_follows_xdg_cache_home(monkeypatch, tmp_path):
    # Pipecat hardcodes ~/.cache, which is read-only under the systemd sandbox.
    monkeypatch.setenv('XDG_CACHE_HOME', str(tmp_path))
    assert pipeline.piper_cache_dir() == tmp_path / 'pipecat' / 'piper'


def test_piper_cache_defaults_to_home_cache(monkeypatch):
    monkeypatch.delenv('XDG_CACHE_HOME', raising=False)
    assert pipeline.piper_cache_dir() == Path.home() / '.cache' / 'pipecat' / 'piper'


def test_tool_calls_speak_an_acknowledgement():
    # Tool calls cost a second model pass; speaking first avoids dead air.
    spoken = []
    class TTS:
        async def queue_frame(self, frame):
            spoken.append((frame.text, frame.append_to_context))
    llm = routing.RoutedLLMService('s1')
    pipeline.acknowledge_tool_calls(llm, TTS())
    handler = llm._event_handlers['on_function_calls_started'].handlers[0]
    asyncio.run(handler(llm, []))
    assert spoken == [('Checking.', False)]
