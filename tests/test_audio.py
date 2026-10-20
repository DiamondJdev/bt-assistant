import asyncio
import base64
import json

import pytest

from bt.voice.serializer import JSONFrameSerializer


@pytest.mark.parametrize('data', ['[]', 'null', '{}', '{', '{"type":"audio"}', '{"type":"audio","pcm":"!"}', '{"type":"audio","pcm":12}', '{"type":"audio","pcm":"AAA=","sampleRate":-1}', '{"type":"audio","pcm":"AAA=","channels":0}', '{"type":"audio","pcm":"AAA=","sampleRate":true}', '{"type":"audio","pcm":"AA=="}', '{"type":"audio","pcm":"' + 'A' * 100000 + '"}'], ids=lambda value: value[:65])
def test_invalid_audio_is_dropped_without_crashing(data):
    assert asyncio.run(JSONFrameSerializer().deserialize(data)) is None


def test_pcm_audio_keeps_format_and_bytes():
    frame = asyncio.run(JSONFrameSerializer().deserialize(json.dumps({'type': 'audio', 'pcm': base64.b64encode(b'\x01\x00' * 512).decode(), 'sampleRate': 16000, 'channels': 1})))
    assert frame.audio == b'\x01\x00' * 512
    assert frame.sample_rate == 16000
    assert frame.num_channels == 1
