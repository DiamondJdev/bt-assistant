from dataclasses import replace

from bt.personality import system_prompt


def test_prompt_injects_session_facts(monkeypatch):
    monkeypatch.setattr(system_prompt, 'CONFIG', replace(system_prompt.CONFIG, operator_name='Jordan', tools_enabled=False))
    prompt = system_prompt.render_system_prompt(surface='voice', session_id='abc', turns=3)
    assert '<!-- bt:context -->' not in prompt and '<!-- bt:tools -->' not in prompt
    assert 'The current date and time is' in prompt
    assert 'Your operator is Jordan.' in prompt
    assert 'Session abc, turn 3.' in prompt
    assert 'No tools are available.' in prompt


def test_prompt_omits_unknown_facts(monkeypatch):
    monkeypatch.setattr(system_prompt, 'CONFIG', replace(system_prompt.CONFIG, operator_name=None, tools_enabled=False))
    prompt = system_prompt.render_system_prompt(surface='text')
    assert 'Your operator is' not in prompt and 'Session ' not in prompt
