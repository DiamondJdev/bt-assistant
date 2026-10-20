import asyncio
from types import SimpleNamespace

from bt.library import MemoryStore
from bt.tools import builtin


def test_memory_search_returns_full_text(tmp_path):
    # The local model will not chain a second call to memory_read, so search must carry the body.
    store = MemoryStore(tmp_path)
    store.write('to-do-list', 'To-do list', '1. Fix dinner\n2. Do chemistry homework')
    result = asyncio.run(builtin.memory_search(SimpleNamespace(memory=store), 'to-do list'))
    assert 'Do chemistry homework' in result


def test_memory_search_caps_long_bodies(tmp_path):
    store = MemoryStore(tmp_path)
    store.write('notes', 'Notes', 'word ' * 2000)
    result = asyncio.run(builtin.memory_search(SimpleNamespace(memory=store), 'notes'))
    assert len(result) < 2 * builtin.SEARCH_BODY_CHARS
