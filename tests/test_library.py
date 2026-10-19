import pytest

from bt.library import MemoryStore


def test_store_on_missing_dir_reads_empty(tmp_path):
    store = MemoryStore(tmp_path / 'not-yet')
    assert store.index_lines() == []
    assert not (tmp_path / 'not-yet').exists()
    store.write('pilot', 'The Pilot is Jordan.', 'Callsign Jordan.')
    assert store.index_lines() == ['pilot: The Pilot is Jordan.']


def test_names_cannot_escape_the_memory_dir(tmp_path):
    store = MemoryStore(tmp_path / 'memory')
    memory = store.write('../../etc/passwd', 'Escape attempt.', 'body')
    assert memory.name == 'etc-passwd'
    assert (tmp_path / 'memory' / 'etc-passwd.md').is_file()
    with pytest.raises(ValueError):
        store.write('../..', 'No usable name.', 'body')


def test_index_sees_external_edits(tmp_path):
    store = MemoryStore(tmp_path)
    store.write('pilot', 'Old fact.', 'body')
    assert store.index_lines() == ['pilot: Old fact.']
    (tmp_path / 'extra.md').write_text('---\ndescription: Added by hand.\n---\n\nbody\n')
    assert 'extra: Added by hand.' in store.index_lines()


def test_index_is_not_reparsed_when_nothing_changed(tmp_path, monkeypatch):
    store = MemoryStore(tmp_path)
    store.write('pilot', 'Fact.', 'body')
    store.index_lines()
    loads = []
    monkeypatch.setattr(store, '_load', lambda path: loads.append(path))
    store.index_lines()
    assert loads == []
