import assert from 'node:assert/strict';
import { test } from 'node:test';

const { Playback } = await import('../bt/client/audio.mjs');

test('interruption stops every queued audio source', () => {
  const sources = [];
  const context = {
    currentTime: 2,
    destination: {},
    createBuffer: (_, length) => ({ getChannelData: () => new Float32Array(length), duration: length / 16000 }),
    createBufferSource: () => {
      const source = { connect() {}, start() {}, stop() { this.stopped = true; } };
      sources.push(source);
      return source;
    },
  };
  const player = new Playback(context);
  player.play('AAAAAA==', 16000);
  player.play('AAAAAA==', 16000);
  player.stop();
  assert.deepEqual(sources.map(s => s.stopped), [true, true]);
  assert.equal(player.sources.size, 0);
  assert.equal(player.playAt, 0);
});
