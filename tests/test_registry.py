import asyncio
from types import SimpleNamespace

from bt.tools import registry


def _ctx():
    return SimpleNamespace(used=[])


async def _echo(ctx, query):
    return f'got {query}'


def _with_tool(monkeypatch):
    spec = registry.ToolSpec('echo', 'Echo.', {'query': {'type': 'string'}}, ('query',), _echo, None, 1.0)
    monkeypatch.setattr(registry, '_REGISTRY', {'echo': spec})


def test_dispatch_rejects_unknown_tool_and_bad_json(monkeypatch):
    _with_tool(monkeypatch)
    assert 'No tool named nope' in asyncio.run(registry.dispatch_call('nope', '{}', _ctx()))
    assert 'not valid JSON' in asyncio.run(registry.dispatch_call('echo', '{bad', _ctx()))
    assert 'must be an object' in asyncio.run(registry.dispatch_call('echo', '[1]', _ctx()))


def test_dispatch_requires_args_and_drops_unknown(monkeypatch):
    _with_tool(monkeypatch)
    ctx = _ctx()
    assert asyncio.run(registry.dispatch_call('echo', '{}', ctx)) == 'echo requires query.'
    assert asyncio.run(registry.dispatch_call('echo', '{"query": "hi", "extra": 1}', ctx)) == 'got hi'
    assert ctx.used == ['echo']
