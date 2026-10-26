from types import SimpleNamespace

from bt.llm.telemetry import TurnMetrics


def test_monotonic_call_and_turn_measurements(monkeypatch):
    from bt.llm import telemetry
    clock = [10.0]
    monkeypatch.setattr(telemetry.time, 'monotonic', lambda: clock[0])
    turn = TurnMetrics('turn')
    call = turn.start_call(SimpleNamespace(key='ollama', model='m'))
    clock[0] += 0.1
    call.output()
    clock[0] += 0.1
    call.visible()
    call.usage(SimpleNamespace(prompt_tokens=20, completion_tokens=10))
    clock[0] += 0.8
    call.finish('completed')
    turn.tool_elapsed(call, 200, client=True)
    turn.tool_elapsed(call, 50, client=False)
    summary = turn.snapshot()
    assert round(summary['duration_ms']) == 1000
    assert summary['tool_wait_ms'] == 200
    assert summary['tool_execution_ms'] == 50
    assert round(summary['calls'][0]['duration_ms']) == 1000
    assert round(summary['calls'][0]['tokens_per_second']) == 10
    assert summary['calls'][0]['tool_wait_ms'] == 200
    assert 'context_limit' not in summary['calls'][0]
    from bt.llm.streaming import MAX_TOKENS
    assert summary['calls'][0]['output_limit'] == MAX_TOKENS


def test_context_limit_requires_matching_runtime_configuration(monkeypatch):
    from dataclasses import replace
    from bt.llm import telemetry
    monkeypatch.setattr(telemetry, 'CONFIG', replace(
        telemetry.CONFIG, context_limit_provider='ollama', context_limit_model='verified', context_limit=4096,
    ))
    turn = TurnMetrics('turn')
    assert turn.start_call(SimpleNamespace(key='ollama', model='verified')).snapshot()['context_limit'] == 4096
    assert 'context_limit' not in turn.start_call(SimpleNamespace(key='ollama', model='other')).snapshot()
