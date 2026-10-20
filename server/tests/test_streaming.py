import asyncio
from types import SimpleNamespace

import pytest

from bt.llm.streaming import ThinkFilter, stream_complete


def test_think_filter_handles_split_tags():
    f = ThinkFilter()
    out = f.feed('<thi') + f.feed('nk>plan</th') + f.feed('ink>Hel') + f.feed('lo') + f.flush()
    assert out == 'Hello'


def test_think_filter_drops_unclosed_and_empty_blocks():
    f = ThinkFilter()
    assert f.feed('<think></think>') + f.feed('Hi') + f.flush() == 'Hi'
    g = ThinkFilter()
    assert g.feed('<think>never closed') + g.flush() == ''


def test_think_filter_passes_plain_angle_brackets():
    f = ThinkFilter()
    assert f.feed('a < b') + f.feed(' and c <t') + f.flush() == 'a < b and c <t'


def _chunk(content=None, tool_calls=None):
    return SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=content, tool_calls=tool_calls))])


def _piece(index, id=None, name=None, arguments=None):
    return SimpleNamespace(index=index, id=id, function=SimpleNamespace(name=name, arguments=arguments))


def _provider(chunks, seen=None):
    async def create(**kwargs):
        if seen is not None:
            seen.append(kwargs)
        async def stream():
            for chunk in chunks:
                yield chunk
        return stream()
    client = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create)))
    return SimpleNamespace(key='ollama', model='m', client=client)


def test_stream_complete_reassembles_tool_calls_and_forwards_text():
    seen = []
    provider = _provider([
        _chunk('Let me '),
        _chunk('check.'),
        _chunk(tool_calls=[_piece(0, 'c1', 'memory_search', '{"q')]),
        _chunk(tool_calls=[_piece(0, arguments='": "x"}')]),
    ], seen)
    collected = []
    async def collect(text):
        collected.append(text)
    message = asyncio.run(stream_complete(provider, [], on_text=collect))
    assert collected == ['Let me ', 'check.']
    assert message.content == 'Let me check.'
    assert message.tool_calls[0].id == 'c1'
    assert message.tool_calls[0].function.name == 'memory_search'
    assert message.tool_calls[0].function.arguments == '{"q": "x"}'
    assert seen[0]['stream'] is True and seen[0]['max_tokens'] == 2048


def test_stream_complete_raises_on_no_chunks():
    with pytest.raises(ValueError):
        asyncio.run(stream_complete(_provider([]), []))
