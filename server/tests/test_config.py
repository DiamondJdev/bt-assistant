import pytest

from bt.config import Config


@pytest.mark.parametrize('host', ['127.0.0.1', '::1', 'localhost', '100.101.102.103', 'fd7a:115c:a1e0::1'])
def test_loopback_and_tailscale_binds_are_allowed(host):
    Config(host=host).validate_access()


@pytest.mark.parametrize('host', ['0.0.0.0', '::', '192.168.1.20', 'bt.local'])
def test_binds_outside_tailscale_are_refused(host):
    # Access is open, so the tailnet is the only boundary.
    with pytest.raises(ValueError, match='BT_HOST'):
        Config(host=host).validate_access()
