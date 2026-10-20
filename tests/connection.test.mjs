import assert from 'node:assert/strict';
import { test } from 'node:test';
import { VoiceConnection } from '../bt/client/connection.mjs';

test('dropped connection retries; stop cancels retries and stale events', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const sockets = [];
  class Socket {
    constructor(url) { this.url = url; this.readyState = 1; sockets.push(this); }
    close() { this.readyState = 3; this.onclose?.({ code: 1000 }); }
    send(data) { this.data = data; }
  }
  const original = globalThis.WebSocket;
  globalThis.WebSocket = Socket;
  t.after(() => { globalThis.WebSocket = original; });
  const states = [];
  let session = 'first';
  const connection = new VoiceConnection(() => session, () => {}, s => states.push(s));
  connection.start();
  sockets[0].onmessage({ data: '{"type":"ready"}' });
  assert.equal(states.at(-1), 'ready');
  sockets[0].onclose({ code: 1006 });
  session = 'restored-session';
  t.mock.timers.tick(1000);
  assert.equal(sockets.length, 2);
  assert.equal(sockets[1].url, 'restored-session');
  connection.stop();
  sockets[1].onclose({ code: 1006 });
  t.mock.timers.tick(30000);
  assert.equal(sockets.length, 2);
  assert.equal(connection.wanted, false);
});

test('access or capacity rejection does not retry forever', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let socket;
  const original = globalThis.WebSocket;
  globalThis.WebSocket = class { constructor() { socket = this; } close() {} };
  t.after(() => { globalThis.WebSocket = original; });
  const connection = new VoiceConnection(() => 'test', () => {}, () => {});
  connection.start();
  socket.onclose({ code: 1008 });
  t.mock.timers.tick(30000);
  assert.equal(connection.wanted, false);
});

test('connection timeout retries rather than leaving voice stuck', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const original = globalThis.WebSocket;
  const sockets = [];
  globalThis.WebSocket = class {
    constructor() { sockets.push(this); }
    close() { this.onclose?.({ code: 1000 }); }
  };
  t.after(() => { globalThis.WebSocket = original; });
  const connection = new VoiceConnection(() => 'test', () => {}, () => {});
  connection.start();
  t.mock.timers.tick(30000);
  t.mock.timers.tick(1000);
  assert.equal(sockets.length, 2);
  connection.stop();
});

test('busy rejection after a drop keeps retrying until the old session clears', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const sockets = [];
  const original = globalThis.WebSocket;
  globalThis.WebSocket = class { constructor() { sockets.push(this); } close() {} };
  t.after(() => { globalThis.WebSocket = original; });
  const connection = new VoiceConnection(() => 'test', () => {}, () => {});
  connection.start();
  sockets[0].onclose({ code: 1013 });
  assert.equal(connection.wanted, false);
  connection.start();
  sockets[1].onmessage({ data: '{"type":"ready"}' });
  sockets[1].onclose({ code: 1006 });
  t.mock.timers.tick(1000);
  sockets[2].onclose({ code: 1013 });
  assert.equal(connection.wanted, true);
  t.mock.timers.tick(2000);
  assert.equal(sockets.length, 4);
  connection.stop();
});
