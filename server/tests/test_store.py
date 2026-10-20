import sqlite3

import pytest

from bt.transcript.store import TranscriptStore


@pytest.fixture
def store():
    db = TranscriptStore(':memory:')
    yield db
    db.close()


def test_model_gets_newest_messages_in_order(store):
    sid = store.new_session()
    for i in range(55):
        store.add_turn(sid, 'user', f'message {i}')
    messages = store.as_chat_messages(sid)
    assert len(messages) == 50
    assert messages[0]['content'] == 'message 5'
    assert messages[-1]['content'] == 'message 54'


def test_unknown_session_cannot_receive_or_return_turns(store):
    with pytest.raises(KeyError):
        store.history('missing')
    with pytest.raises(KeyError):
        with store.conversation('missing'):
            pass
    with pytest.raises(sqlite3.IntegrityError):
        store.add_turn('missing', 'user', 'orphan')


def test_conversation_lease_rejects_overlap_and_releases_on_error(store):
    sid = store.new_session()
    with pytest.raises(RuntimeError, match='provider failed'):
        with store.conversation(sid):
            with pytest.raises(RuntimeError, match='busy'):
                with store.conversation(sid):
                    pass
            raise RuntimeError('provider failed')
    with store.conversation(sid):
        store.add_turn(sid, 'user', 'retry')
    assert store.history(sid)[0].text == 'retry'


def test_sessions_survive_reopening_database(tmp_path):
    path = str(tmp_path / 'bt.sqlite3')
    store = TranscriptStore(path)
    sid = store.new_session()
    store.add_turn(sid, 'user', 'Remember this')
    store.close()
    store = TranscriptStore(path)
    assert store.list_sessions()[0]['id'] == sid
    assert store.list_sessions()[0]['label'] == 'Remember this'
    store.close()
