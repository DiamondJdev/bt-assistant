import { Playback, audioMessage, level } from './audio.mjs';
import { VoiceConnection } from './connection.mjs';

const $ = id => document.getElementById(id);
const status = message => { $('status').textContent = message; };
const READY_POLL_MS = 15000;
let sessionId = localStorage.getItem('bt-session');
let playback, micContext, micStream, talking = false, voiceReady = false, sending = false;
let openTurn = null, server = { state: 'warn', text: 'Checking…' }, voiceState = 'disconnected';
let talkStarted = 0, timerId = null;

async function api(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { 'Content-Type': 'application/json', ...options.headers } });
  // Proxies and server crashes can return HTML or plain text.
  const data = await response.json().catch(() => ({}));
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

// ---- Conversation log ----

function welcome() {
  const element = document.createElement('div');
  element.className = 'welcome';
  element.innerHTML = '<div class="avatar">BT</div><h2>How can I help?</h2><p>Type a message, or start a voice session and hold to talk.</p>';
  $('log').replaceChildren(element);
}

function metaText({ ts, compute, input_mode: mode } = {}) {
  const parts = [];
  if (ts) parts.push(new Date(ts * 1000).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }));
  if (mode === 'voice') parts.push('voice');
  if (compute) parts.push(compute === 'openai' ? 'cloud' : 'local');
  return parts.join(' · ');
}

function turn(role, text, meta) {
  $('log').querySelector('.welcome')?.remove();
  const element = document.createElement('div');
  element.className = `msg ${role === 'user' ? 'user' : 'bt'}`;
  const column = document.createElement('div');
  const body = document.createElement('div');
  body.className = 'text';
  body.textContent = text;
  column.append(body);
  const info = metaText(meta);
  if (info) {
    const tag = document.createElement('span');
    tag.className = 'meta';
    tag.textContent = info;
    column.append(tag);
  }
  if (role !== 'user') element.insertAdjacentHTML('afterbegin', '<span class="avatar" aria-label="BT">BT</span>');
  element.append(column);
  $('log').append(element);
  $('log').scrollTop = $('log').scrollHeight;
  return body;
}

async function refreshSessions() {
  const sessions = await api('/sessions');
  const items = sessions.map(session => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = session.label;
    button.title = session.label;
    button.dataset.id = session.id;
    button.setAttribute('aria-current', String(session.id === sessionId));
    const item = document.createElement('li');
    item.append(button);
    return item;
  });
  $('sessions').replaceChildren(...items);
  $('title').textContent = sessions.find(s => s.id === sessionId)?.label || 'New chat';
  controls();
}

async function restoreHistory() {
  openTurn = null;
  welcome();
  if (!sessionId) return;
  const history = await api(`/history?session_id=${encodeURIComponent(sessionId)}`);
  for (const item of history) turn(item.role, item.text, item);
}

async function openSession(id) {
  if (voice.wanted || sending) return;
  sessionId = id;
  if (id) saveSession(id); else localStorage.removeItem('bt-session');
  closeSidebar();
  try { await restoreHistory(); await refreshSessions(); } catch (error) { status(error.message); }
}

$('sessions').onclick = event => {
  const id = event.target.closest('button')?.dataset.id;
  if (id) openSession(id);
};
$('new').onclick = async () => {
  try {
    saveSession((await api('/sessions', { method: 'POST' })).session_id);
    await refreshSessions();
    await restoreHistory();
    closeSidebar();
    $('message').focus();
  } catch (error) { status(error.message); }
};

// ---- Connection status ----

function showStatus() {
  $('server-dot').dataset.state = server.state;
  $('server-text').textContent = server.text;
  $('server-text').title = server.text;
  const voiceLabel = { ready: 'Connected', connecting: 'Connecting…', reconnecting: 'Reconnecting…' }[voiceState] || 'Off';
  $('voice-dot').dataset.state = voiceState === 'ready' ? 'ok' : voice.wanted ? 'warn' : 'off';
  $('voice-text').textContent = voiceLabel;
  const [state, text] = server.state !== 'ok' ? [server.state, server.text]
    : voiceState === 'reconnecting' ? ['warn', 'Reconnecting voice…']
    : ['ok', voiceState === 'ready' ? 'Connected · voice' : 'Connected'];
  $('conn').dataset.state = state;
  $('conn').lastElementChild.textContent = text;
  $('conn').title = `Server: ${server.text}. Voice: ${voiceLabel}.`;
}

async function checkServer() {
  try {
    const response = await fetch('/ready', { cache: 'no-store' });
    const data = await response.json().catch(() => ({}));
    server = response.ok ? { state: 'ok', text: 'Ready' } : { state: 'warn', text: data.reason || 'Unavailable' };
  } catch {
    server = { state: 'bad', text: 'Offline' };
  }
  showStatus();
}

// ---- Text chat ----

function controls() {
  const busy = sending || voice.wanted;
  $('send').disabled = busy;
  $('message').disabled = busy;
  $('new').disabled = busy;
  for (const button of $('sessions').querySelectorAll('button')) button.disabled = busy;
  $('chat').hidden = voice.wanted;
  $('ptt').hidden = !voice.wanted;
}

function growInput() {
  $('message').style.height = 'auto';
  $('message').style.height = `${$('message').scrollHeight}px`;
}

$('message').oninput = growInput;
$('message').onkeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    $('chat').requestSubmit();
  }
};

$('chat').onsubmit = async event => {
  event.preventDefault();
  if (sending || voice.wanted) return;
  const text = $('message').value.trim();
  if (!text) return;
  sending = true;
  controls();
  turn('user', text);
  turn('bt', '');
  $('message').value = '';
  growInput();
  status('BT is thinking…');
  try {
    const response = await api('/chat', { method: 'POST', body: JSON.stringify({ text, session_id: sessionId }) });
    saveSession(response.session_id);
    await restoreHistory();
    await refreshSessions();
    status(response.compute === 'openai' ? 'Answered using cloud fallback.' : '');
  } catch (error) {
    status(error.message);
    $('message').value ||= text;
    if (sessionId) await Promise.all([restoreHistory(), refreshSessions()]).catch(() => {});
  } finally { sending = false; controls(); $('message').focus(); }
};

// ---- Voice ----

function phase(name, label) {
  $('voice-phase').dataset.phase = name;
  $('voice-phase').textContent = label;
}

function idlePhase() {
  if (talking) return;
  if (playback?.playing) phase('speaking', 'BT is speaking');
  else if (voiceReady) phase('ready', 'Ready');
}

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
    turn('user', message.data?.text || '', { input_mode: 'voice' });
    openTurn = null;
  }
  if (message.type === 'bot-llm-text') {
    openTurn ??= turn('bt', '', { input_mode: 'voice' });
    openTurn.textContent += message.data?.text || '';
    $('log').scrollTop = $('log').scrollHeight;
  }
  if (message.type === 'bot-llm-stopped') { openTurn = null; idlePhase(); }
  if (message.type === 'error') status('Voice processing failed. End voice and start it again.');
}

function onVoiceState(state, reason) {
  voiceState = state;
  voiceReady = state === 'ready';
  releaseTalk();
  if (state !== 'ready') playback?.stop();
  $('talk').disabled = !voiceReady;
  if (state === 'ready') phase('ready', 'Ready');
  else if (state !== 'disconnected') phase('connecting', state === 'reconnecting' ? 'Reconnecting…' : 'Connecting…');
  controls();
  showStatus();
  status(state === 'ready' ? '' : reason || '');
  if (state === 'disconnected') {
    micStream?.getTracks().forEach(track => track.stop());
    micStream = null;
    micContext?.close(); micContext = null;
    restoreHistory().catch(() => {});
  }
}

const voice = new VoiceConnection(
  () => `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/voice/ws${sessionId ? `?session_id=${encodeURIComponent(sessionId)}` : ''}`,
  wireMessage,
  onVoiceState,
);

async function connect() {
  if (!navigator.mediaDevices?.getUserMedia) throw new Error('Open BT over HTTPS to use the microphone.');
  playback ??= new Playback(new AudioContext());
  playback.onchange = playing => { $('stop').disabled = !playing; idlePhase(); };
  await playback.context.resume();
  micStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
  micStream.getAudioTracks().forEach(track => { track.enabled = false; });
  micContext = new AudioContext({ sampleRate: 16000 });
  if (micContext.sampleRate !== 16000) throw new Error('This browser cannot record at 16 kHz. Try Safari or Chrome.');
  await micContext.resume();
  await micContext.audioWorklet.addModule('/static/capture.js');
  const capture = new AudioWorkletNode(micContext, 'capture');
  capture.port.onmessage = event => {
    if (!talking || !voiceReady) return;
    $('meter').style.width = `${Math.round(level(event.data) * 100)}%`;
    voice.send(audioMessage(event.data));
  };
  micContext.createMediaStreamSource(micStream).connect(capture);
  capture.connect(micContext.destination);
  voice.start();
}

function disconnect() { voice.stop(); playback?.stop(); }
$('voice').onclick = async () => {
  $('voice').disabled = true;
  try { await connect(); }
  catch (error) { disconnect(); status(error.message); }
  finally { $('voice').disabled = false; }
};
$('end').onclick = () => { disconnect(); $('message').focus(); };

function tick() {
  const seconds = Math.floor((Date.now() - talkStarted) / 1000);
  $('timer').textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

function holdTalk() {
  if (!voiceReady || talking) return;
  playback?.stop();
  talking = true;
  micStream?.getAudioTracks().forEach(track => { track.enabled = true; });
  $('talk').setAttribute('aria-pressed', 'true');
  phase('listening', 'Listening… release to send');
  talkStarted = Date.now();
  tick();
  timerId = setInterval(tick, 250);
}

function releaseTalk() {
  const wasTalking = talking;
  talking = false;
  micStream?.getAudioTracks().forEach(track => { track.enabled = false; });
  $('talk').setAttribute('aria-pressed', 'false');
  clearInterval(timerId);
  $('timer').textContent = '';
  $('meter').style.width = '0';
  if (wasTalking && voiceReady) {
    voice.send(audioMessage(new Int16Array(16000).buffer));
    phase('thinking', 'BT is thinking…');
  }
}

const isSpace = event => event.code === 'Space' || event.key === ' ';
const typingTarget = target => target.closest?.('textarea, input, select, [contenteditable]');
$('talk').onpointerdown = event => { event.preventDefault(); $('talk').setPointerCapture(event.pointerId); holdTalk(); };
$('talk').onpointerup = releaseTalk;
$('talk').onpointercancel = releaseTalk;
$('talk').onlostpointercapture = releaseTalk;
$('talk').onblur = releaseTalk;
$('talk').oncontextmenu = event => event.preventDefault();
$('talk').onkeydown = event => { if (event.key === 'Enter') { event.preventDefault(); if (!event.repeat) holdTalk(); } };
$('talk').onkeyup = event => { if (event.key === 'Enter') releaseTalk(); };
// Space works anywhere on the page while voice is on, except where it is typing.
document.addEventListener('keydown', event => {
  if (!voice.wanted || !isSpace(event) || typingTarget(event.target)) return;
  event.preventDefault();
  if (!event.repeat) holdTalk();
});
document.addEventListener('keyup', event => { if (isSpace(event) && talking) releaseTalk(); });
window.addEventListener('blur', releaseTalk);
$('stop').onclick = () => playback?.stop();

// ---- Layout ----

function closeSidebar() { $('sidebar').classList.remove('open'); $('scrim').hidden = true; }
$('open-side').onclick = () => { $('sidebar').classList.add('open'); $('scrim').hidden = false; };
$('close-side').onclick = closeSidebar;
$('scrim').onclick = closeSidebar;

// ---- Startup ----

async function initialize() {
  welcome();
  const config = await api('/config');
  $('model-text').textContent = config.model || '—';
  $('voice').hidden = !config.voice_enabled;
  if (sessionId) {
    try { await restoreHistory(); }
    catch (error) { sessionId = null; localStorage.removeItem('bt-session'); welcome(); status(error.message); }
  }
  await refreshSessions();
  $('message').focus();
}

window.addEventListener('pagehide', disconnect);
window.addEventListener('online', checkServer);
window.addEventListener('offline', checkServer);
document.addEventListener('visibilitychange', () => { if (document.hidden) releaseTalk(); else checkServer(); });
setInterval(checkServer, READY_POLL_MS);
checkServer();
initialize().catch(error => { server = { state: 'bad', text: 'Offline' }; showStatus(); status(error.message); });
