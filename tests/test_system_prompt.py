from dataclasses import replace

from bt.library import MemoryStore
from bt.personality import system_prompt


def test_prompt_injects_session_facts(monkeypatch):
    monkeypatch.setattr(system_prompt, 'CONFIG', replace(system_prompt.CONFIG, operator_name='Jordan', tools_enabled=False))
    prompt = system_prompt.render_system_prompt(surface='voice')
    assert '<!-- bt:context -->' not in prompt and '<!-- bt:tools -->' not in prompt
    assert 'Your operator is Jordan.' in prompt
    assert 'No tools are available.' in prompt


def test_prompt_omits_unknown_facts(monkeypatch):
    monkeypatch.setattr(system_prompt, 'CONFIG', replace(system_prompt.CONFIG, operator_name=None, tools_enabled=False))
    prompt = system_prompt.render_system_prompt(surface='text')
    assert 'Your operator is' not in prompt and 'Session ' not in prompt


def test_prompt_keeps_per_turn_facts_out_so_ollama_can_reuse_its_cache(monkeypatch):
    monkeypatch.setattr(system_prompt, 'CONFIG', replace(system_prompt.CONFIG, tools_enabled=False))
    prompt = system_prompt.render_system_prompt(surface='voice')
    assert 'The current date and time is' not in prompt and 'Session ' not in prompt


def test_turn_note_carries_time_session_and_matching_memories(monkeypatch, tmp_path):
    store = MemoryStore(tmp_path)
    store.write('pilot-name', 'The Pilot is Jordan.', 'Jordan prefers short answers.')
    store.write('garage', 'Garage code', 'The code is 4417.')
    monkeypatch.setattr(system_prompt, 'get_memory', lambda: store)
    note = system_prompt.turn_note('Do you remember my name?', session_id='abc', turns=3)
    assert 'The current date and time is' in note
    assert 'Session abc, turn 3.' in note
    assert 'Jordan prefers short answers.' in note
    assert '4417' not in note


def test_with_turn_note_appends_to_latest_user_message_without_mutating():
    messages = [
        {'role': 'system', 'content': 'soul'},
        {'role': 'user', 'content': 'old'},
        {'role': 'assistant', 'content': 'reply'},
        {'role': 'user', 'content': 'new'},
        {'role': 'tool', 'content': 'result'},
    ]
    out = system_prompt.with_turn_note(messages, 'NOTE')
    assert [m['content'] for m in out] == ['soul', 'old', 'reply', 'new\n\nNOTE', 'result']
    assert messages[3]['content'] == 'new'
