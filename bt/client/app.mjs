import { Playback, audioMessage } from './audio.mjs';
import { VoiceConnection } from './connection.mjs';

const $ = id => document.getElementById(id);
const status = message => { $('status').textContent = message; };
let sessionId = localStorage.getItem('bt-session');
let playback, micContext, micStream, talking = false, voiceReady = false, sending = false;
let openTurn = null;

async function api(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { 'Content-Type': 'application/json', ...options.headers } });
  // Proxies and server crashes can return HTML or plain text.
  const data = await response.json().catch(() => ({}));
  if (response.status === 401) {
    if (voice.wanted) disconnect();
    $('login').hidden = false;
    $('assistant').hidden = $('logout').hidden = true;
    throw new Error('Unlock BT with your server access token.');
  }
  if (!response.ok) {
    const detail = data.detail;
    if (detail?.session_id) saveSession(detail.session_id);
    throw new Error(typeof detail === 'string' ? detail : detail?.message || `Request failed (${response.status})`);
  }
  return data;
}

function saveSession(id) {
  sessionId = id;
  localStorage.setItem('bt-session', id);
}

function turn(role, text) {
  $('log').querySelector('.empty')?.remove();
  const element = document.createElement('div');
  element.className = `turn ${role === 'user' ? 'user' : 'bot'}`;
  const who = document.createElement('b');
  who.textContent = role === 'user' ? 'You' : 'BT';
  const body = document.createElement('span');
  body.textContent = text;
  element.append(who, body);
  $('log').append(element);
  $('log').scrollTop = $('log').scrollHeight;
  return body;
}

async function refreshSessions() {
  const sessions = await api('/sessions');
  $('sessions').replaceChildren(new Option('New conversation', ''));
  for (const session of sessions) $('sessions').add(new Option(session.label, session.id));
  $('sessions').value = sessionId || '';
}

async function restoreHistory() {
  $('log').replaceChildren();
  openTurn = null;
  if (!sessionId) return;
  const history = await api(`/history?session_id=${encodeURIComponent(sessionId)}`);
  for (const item of history) turn(item.role, item.text);
}

async function initialize() {
  const config = await api('/config');
  $('login').hidden = true;
  $('assistant').hidden = $('logout').hidden = false;
  $('voice').disabled = !config.voice_enabled;
  $('voice').textContent = config.voice_enabled ? 'Connect voice' : 'Voice disabled on server';
  await refreshSessions();
  if (sessionId) {
    try { await restoreHistory(); }
    catch (error) { sessionId = null; localStorage.removeItem('bt-session'); status(error.message); }
  }
  status('Ready.');
}

$('login').onsubmit = async event => {
  event.preventDefault();
  try {
    await api('/auth/login', { method: 'POST', body: JSON.stringify({ token: $('token').value }) });
    $('token').value = '';
    await initialize();
  } catch (error) { status(error.message); }
};
$('logout').onclick = async () => {
  disconnect();
  try { await api('/auth/logout', { method: 'POST' }); } catch (error) { status(error.message); }
  $('log').replaceChildren();
  $('sessions').replaceChildren();
  $('login').hidden = false;
  $('assistant').hidden = $('logout').hidden = true;
};
$('sessions').onchange = async () => {
  if (voice.wanted || sending) return;
  sessionId = $('sessions').value || null;
  if (sessionId) saveSession(sessionId);
  else localStorage.removeItem('bt-session');
  try { await restoreHistory(); } catch (error) { status(error.message); }
};
$('new').onclick = async () => {
  try {
    saveSession((await api('/sessions', { method: 'POST' })).session_id);
    await refreshSessions();
    await restoreHistory();
    $('message').focus();
  } catch (error) { status(error.message); }
};

function controls() {
  $('send').disabled = sending || voice.wanted;
  $('message').disabled = sending || voice.wanted;
  $('new').disabled = sending || voice.wanted;
  $('sessions').disabled = sending || voice.wanted;
}

$('chat').onsubmit = async event => {
  event.preventDefault();
  if (sending || voice.wanted) return;
  const text = $('message').value.trim();
  if (!text) return;
  sending = true;
  controls();
  status('BT is thinking…');
  try {
    const response = await api('/chat', { method: 'POST', body: JSON.stringify({ text, session_id: sessionId }) });
    saveSession(response.session_id);
    $('message').value = '';
    await refreshSessions();
    await restoreHistory();
    status(response.compute === 'openai' ? 'Answered using cloud fallback.' : 'Answered locally.');
  } catch (error) {
    status(error.message);
    if (sessionId) await restoreHistory().catch(() => {});
  } finally { sending = false; controls(); $('message').focus(); }
};

function wireMessage(message) {
  if (message.type === 'session') {
    saveSession(message.sessionId);
    refreshSessions().catch(error => status(error.message));
  }
  if (message.type === 'audio') playback?.play(message.pcm, message.sampleRate);
  if (message.type === 'status') status(message.message);
  if (message.label !== 'rtvi-ai') return;
  if (message.type === 'bot-interrupted') { playback?.stop(); openTurn = null; }
  if (message.type === 'user-transcription' && message.data?.final !== false) {
    turn('user', message.data?.text || '');
    openTurn = null;
  }
  if (message.type === 'bot-llm-text') {
    openTurn ??= turn('bt', '');
    openTurn.textContent += message.data?.text || '';
    $('log').scrollTop = $('log').scrollHeight;
  }
  if (message.type === 'bot-llm-stopped') openTurn = null;
  if (message.type === 'error') status('Voice processing failed. Disconnect and reconnect voice.');
}

const voice = new VoiceConnection(
  () => `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/voice/ws${sessionId ? `?session_id=${encodeURIComponent(sessionId)}` : ''}`,
  wireMessage,
  (state, reason) => {
    voiceReady = state === 'ready';
    releaseTalk();
    if (state !== 'ready') playback?.stop();
    $('talk').disabled = !voiceReady;
    $('voice').textContent = voice.wanted ? 'Disconnect voice' : 'Connect voice';
    controls();
    status(state === 'ready' ? 'Voice ready. Hold to talk.' : reason || `Voice ${state}.`);
    if (state === 'disconnected') {
      micStream?.getTracks().forEach(track => track.stop());
      micStream = null;
      micContext?.close(); micContext = null;
      restoreHistory().catch(() => {});
    }
  },
);

async function connect() {
  if (!navigator.mediaDevices?.getUserMedia) throw new Error('Open BT over HTTPS to use the microphone.');
  playback ??= new Playback(new AudioContext());
  await playback.context.resume();
  micStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
  micStream.getAudioTracks().forEach(track => { track.enabled = false; });
  micContext = new AudioContext({ sampleRate: 16000 });
  if (micContext.sampleRate !== 16000) throw new Error('This browser cannot record at 16 kHz. Try Safari or Chrome.');
  await micContext.resume();
  await micContext.audioWorklet.addModule('/static/capture.js');
  const capture = new AudioWorkletNode(micContext, 'capture');
  capture.port.onmessage = event => { if (talking && voiceReady) voice.send(audioMessage(event.data)); };
  micContext.createMediaStreamSource(micStream).connect(capture);
  capture.connect(micContext.destination);
  voice.start();
}

function disconnect() { voice.stop(); playback?.stop(); }
$('voice').onclick = async () => {
  if (voice.wanted) { disconnect(); return; }
  $('voice').disabled = true;
  try { await connect(); }
  catch (error) { disconnect(); status(error.message); }
  finally { $('voice').disabled = false; }
};
function holdTalk() {
  if (!voiceReady) return;
  playback?.stop();
  talking = true;
  micStream?.getAudioTracks().forEach(track => { track.enabled = true; });
  $('talk').setAttribute('aria-pressed', 'true');
  status('Listening… Release to send.');
}
function releaseTalk() {
  const wasTalking = talking;
  talking = false;
  micStream?.getAudioTracks().forEach(track => { track.enabled = false; });
  $('talk').setAttribute('aria-pressed', 'false');
  if (wasTalking && voiceReady) {
    voice.send(audioMessage(new Int16Array(16000).buffer));
    status('BT is thinking…');
  }
}
$('talk').onpointerdown = event => { event.preventDefault(); $('talk').setPointerCapture(event.pointerId); holdTalk(); };
$('talk').onpointerup = releaseTalk;
$('talk').onpointercancel = releaseTalk;
$('talk').onlostpointercapture = releaseTalk;
$('talk').oncontextmenu = event => event.preventDefault();
$('talk').onkeydown = event => { if ([' ', 'Enter'].includes(event.key)) { event.preventDefault(); if (!event.repeat) holdTalk(); } };
$('talk').onkeyup = event => { if ([' ', 'Enter'].includes(event.key)) releaseTalk(); };
$('talk').onblur = releaseTalk;
$('stop').onclick = () => playback?.stop();
window.addEventListener('pagehide', disconnect);
document.addEventListener('visibilitychange', () => { if (document.hidden) releaseTalk(); });
initialize().catch(error => status(error.message));
