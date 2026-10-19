from dataclasses import replace

import pytest

from bt.config import Config


def test_network_bind_requires_token():
    with pytest.raises(ValueError, match='BT_API_TOKEN'):
        Config(host='0.0.0.0', api_token='').validate_access()
    with pytest.raises(ValueError, match='BT_API_TOKEN'):
        # Tailscale Serve and other local proxies reach BT from loopback.
        Config(host='127.0.0.1', api_token='').validate_access()
    Config(host='127.0.0.1', api_token='a-token').validate_access()
    Config(host='0.0.0.0', api_token='a-token').validate_access()
