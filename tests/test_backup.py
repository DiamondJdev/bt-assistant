import sqlite3

import pytest

from bt.backup import backup_database
from bt.transcript.store import TranscriptStore


def test_backup_captures_live_wal_and_can_be_restored(tmp_path):
    source = tmp_path / 'live.sqlite3'
    destination = tmp_path / 'backup.sqlite3'
    store = TranscriptStore(str(source))
    sid = store.new_session()
    store.add_turn(sid, 'user', 'Keep me')
    backup_database(source, destination)
    restored = TranscriptStore(str(destination))
    assert restored.history(sid)[0].text == 'Keep me'
    assert destination.stat().st_mode & 0o077 == 0
    restored.close()
    store.close()


def test_backup_does_not_replace_existing_files_or_create_missing_source(tmp_path):
    missing = tmp_path / 'missing.sqlite3'
    destination = tmp_path / 'existing.sqlite3'
    destination.write_bytes(b'preserve this')
    with pytest.raises((FileExistsError, sqlite3.OperationalError)):
        backup_database(missing, destination)
    assert destination.read_bytes() == b'preserve this'
    assert not missing.exists()
