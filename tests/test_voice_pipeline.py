from pathlib import Path

from bt.voice import pipeline


def test_piper_cache_follows_xdg_cache_home(monkeypatch, tmp_path):
    # Pipecat hardcodes ~/.cache, which is read-only under the systemd sandbox.
    monkeypatch.setenv('XDG_CACHE_HOME', str(tmp_path))
    assert pipeline.piper_cache_dir() == tmp_path / 'pipecat' / 'piper'


def test_piper_cache_defaults_to_home_cache(monkeypatch):
    monkeypatch.delenv('XDG_CACHE_HOME', raising=False)
    assert pipeline.piper_cache_dir() == Path.home() / '.cache' / 'pipecat' / 'piper'
