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


def test_diagnostics_preserve_usage_only_final_chunk():
    from bt.llm.telemetry import TurnMetrics
    seen = []
    provider = _provider([
        _chunk('<think>private</think>Hello'),
        SimpleNamespace(choices=[], usage=SimpleNamespace(prompt_tokens=12, completion_tokens=4)),
    ], seen)
    turn = TurnMetrics('turn')
    call = turn.start_call(provider)
    asyncio.run(stream_complete(provider, [], metrics=call))
    call.finish('completed')
    summary = turn.snapshot()['calls'][0]
    assert seen[0]['stream_options'] == {'include_usage': True}
    assert summary['prompt_tokens'] == 12 and summary['completion_tokens'] == 4
    assert summary['first_output_ms'] >= 0
    assert summary['first_visible_text_ms'] >= summary['first_output_ms']
    assert summary['throughput_source'] == 'observed'
    assert 'private' not in str(summary)


def test_missing_usage_is_not_estimated_and_old_requests_are_unchanged():
    from bt.llm.telemetry import TurnMetrics
    seen = []
    provider = _provider([_chunk('Hello')], seen)
    call = TurnMetrics('turn').start_call(provider)
    asyncio.run(stream_complete(provider, [], metrics=call))
    call.finish('completed')
    assert 'completion_tokens' not in call.snapshot()
    assert 'tokens_per_second' not in call.snapshot()
    asyncio.run(stream_complete(provider, []))
    assert 'stream_options' not in seen[-1]
