// Dev page for the voice pipeline.
// Speaks the JSON wire format from bt/voice/serializer.py:
// Ugly and AI generated since this is an internal dev tool.

const RATE = 16000; // Hz
const $ = (id) => document.getElementById(id);

let ws = null, micCtx = null, micStream = null, playCtx = null, playAt = 0;
let sessionId = null;
const metrics = { ttfb: {}, processing: {}, tokens: null, characters: null };

// ---------- turns ----------

// Streamed text arrives token by token, so the open turn is mutated in place
// rather than appended as a new line per delta.
let openTurn = null;

function turn(kind, who) {
	const el = document.createElement("div");
	el.className = `turn ${kind}`;
	el.innerHTML = `<span class="who"></span><span class="body"></span>`;
	el.querySelector(".who").textContent = who;
	$("log").append(el);
	$("log").scrollTop = $("log").scrollHeight;
	return el;
}

function appendTo(el, text) {
	el.querySelector(".body").textContent += text;
	$("log").scrollTop = $("log").scrollHeight;
}

function closeTurn() { openTurn = null; }

// Tool calls arrive as a pair of RTVI events keyed by tool_call_id, so the
// chip opened by the first is held here until the second resolves it.
const toolChips = new Map();

// ---------- metrics ----------

function row(tbody, label, value) {
	const tr = document.createElement("tr");
	tr.innerHTML = "<td></td><td></td>";
	tr.children[0].textContent = label;
	tr.children[1].textContent = value;
	tbody.append(tr);
}

function renderMetrics() {
	const lat = $("latency").tBodies[0];
	lat.textContent = "";
	for (const [proc, v] of Object.entries(metrics.ttfb)) {
		row(lat, `${short(proc)} ttfb`, `${(v * 1000).toFixed(0)} ms`);
	}
	for (const [proc, v] of Object.entries(metrics.processing)) {
		row(lat, `${short(proc)} total`, `${(v * 1000).toFixed(0)} ms`);
	}

	const tok = $("tokens").tBodies[0];
	tok.textContent = "";
	const t = metrics.tokens;
	if (t) {
		row(tok, "prompt", t.prompt_tokens ?? 0);
		row(tok, "completion", t.completion_tokens ?? 0);
		row(tok, "total", t.total_tokens ?? 0);
		// Generation rate excludes the wait for the first token, which is what
		// makes it comparable across models rather than across prompt lengths.
		const llm = Object.keys(metrics.processing).find((p) => /llm/i.test(p));
		if (llm && t.completion_tokens) {
			const gen = metrics.processing[llm] - (metrics.ttfb[llm] ?? 0);
			if (gen > 0) row(tok, "tok/s", (t.completion_tokens / gen).toFixed(1));
		}
	}
	if (metrics.characters != null) row(tok, "tts chars", metrics.characters);
}

const short = (p) => p.replace(/Service$/, "").replace(/^(OLLama|Piper|Whisper)/, "$1");

function onMetrics(data) {
	for (const m of data.ttfb ?? []) metrics.ttfb[m.processor] = m.value;
	for (const m of data.processing ?? []) metrics.processing[m.processor] = m.value;
	for (const m of data.tokens ?? []) metrics.tokens = m;
	for (const m of data.characters ?? []) metrics.characters = m.value;
	renderMetrics();
}

// ---------- audio out ----------

function play(b64, rate) {
	playCtx ??= new AudioContext({ sampleRate: rate });
	const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
	const pcm = new Int16Array(bytes.buffer);
	const buf = playCtx.createBuffer(1, pcm.length, rate);
	const ch = buf.getChannelData(0);
	for (let i = 0; i < pcm.length; i++) ch[i] = pcm[i] / 32768;
	const src = playCtx.createBufferSource();
	src.buffer = buf;
	src.connect(playCtx.destination);
	// Chunks arrive faster than realtime, so queue them end to end instead of
	// starting each on arrival.
	playAt = Math.max(playAt, playCtx.currentTime);
	src.start(playAt);
	playAt += buf.duration;
}

function stopPlayback() { playAt = 0; }

// ---------- audio in ----------

const WORKLET = `
class Cap extends AudioWorkletProcessor {
	constructor() { super(); this.buf = []; this.n = 0; }
	process(inputs) {
		const ch = inputs[0][0];
		if (!ch) return true;
		this.buf.push(new Float32Array(ch)); this.n += ch.length;
		if (this.n >= 512) {
			const out = new Int16Array(this.n);
			let i = 0;
			for (const b of this.buf) for (const s of b) {
				out[i++] = Math.max(-1, Math.min(1, s)) * 32767;
			}
			this.port.postMessage(out.buffer, [out.buffer]);
			this.buf = []; this.n = 0;
		}
		return true;
	}
}
registerProcessor("cap", Cap);`;

async function startMic() {
	if (!navigator.mediaDevices?.getUserMedia) {
		throw new Error(
			"mic access needs a secure context (https, or localhost) — " +
			"over Tailscale run `tailscale serve https / http://127.0.0.1:8080`",
		);
	}
	micStream = await navigator.mediaDevices.getUserMedia({
		audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
	});
	micCtx = new AudioContext({ sampleRate: RATE });
	const url = URL.createObjectURL(new Blob([WORKLET], { type: "text/javascript" }));
	await micCtx.audioWorklet.addModule(url);
	URL.revokeObjectURL(url);

	const node = new AudioWorkletNode(micCtx, "cap");
	node.port.onmessage = (e) => {
		if (ws?.readyState !== WebSocket.OPEN) return;
		let s = "";
		for (const b of new Uint8Array(e.data)) s += String.fromCharCode(b);
		ws.send(JSON.stringify({
			type: "audio", pcm: btoa(s), sampleRate: micCtx.sampleRate, channels: 1,
		}));
	};
	micCtx.createMediaStreamSource(micStream).connect(node);
}

// ---------- wire ----------

function handle(msg) {
	if (msg.type === "audio") return play(msg.pcm, msg.sampleRate);
	if (msg.type === "session") {
		sessionId = msg.sessionId;
		$("session").textContent = `session ${sessionId.slice(0, 8)}`;
		return;
	}
	if (msg.label !== "rtvi-ai") return;

	switch (msg.type) {
		case "user-transcription": {
			const final = msg.data?.final ?? true;
			if (!openTurn || openTurn.dataset.kind !== "user") {
				openTurn = turn("user partial", "you");
				openTurn.dataset.kind = "user";
			}
			openTurn.querySelector(".body").textContent = msg.data?.text ?? "";
			if (final) { openTurn.classList.remove("partial"); closeTurn(); }
			break;
		}
		case "bot-llm-text":
			if (!openTurn || openTurn.dataset.kind !== "bot") {
				openTurn = turn("bot", "bt");
				openTurn.dataset.kind = "bot";
			}
			appendTo(openTurn, msg.data?.text ?? "");
			break;
		case "bot-llm-stopped":
			closeTurn();
			break;
		case "bot-interrupted":
			stopPlayback();
			closeTurn();
			break;
		case "user-started-speaking":
			setStatus("listening", true);
			break;
		case "bot-started-speaking":
			setStatus("speaking", true);
			break;
		case "bot-stopped-speaking":
		case "user-stopped-speaking":
			setStatus("connected", true);
			break;
		case "llm-function-call-in-progress": {
			const d = msg.data ?? {};
			closeTurn();
			const args = d.arguments && Object.keys(d.arguments).length
				? JSON.stringify(d.arguments)
				: "";
			const el = turn("tool partial", "tool");
			el.querySelector(".body").textContent = `${d.function_name ?? "?"}(${args})`;
			toolChips.set(d.tool_call_id, el);
			break;
		}
		case "llm-function-call-stopped": {
			const d = msg.data ?? {};
			const el = toolChips.get(d.tool_call_id);
			if (el) {
				el.classList.remove("partial");
				appendTo(el, ` -> ${d.cancelled ? "cancelled" : String(d.result ?? "")}`);
				toolChips.delete(d.tool_call_id);
			}
			break;
		}
		case "metrics":
			onMetrics(msg.data ?? {});
			break;
	}
}

function setStatus(text, on) {
	$("status").textContent = text;
	$("status").classList.toggle("on", !!on);
}

async function connect() {
	const proto = location.protocol === "https:" ? "wss" : "ws";
	const q = sessionId ? `?session_id=${encodeURIComponent(sessionId)}` : "";
	ws = new WebSocket(`${proto}://${location.host}/voice/ws${q}`);

	ws.onmessage = (e) => { try { handle(JSON.parse(e.data)); } catch {} };
	ws.onclose = () => { setStatus("disconnected", false); teardown(); };
	ws.onerror = () => setStatus("error", false);
	await new Promise((res, rej) => { ws.onopen = res; ws.addEventListener("error", rej); });

	await startMic();
	setStatus("connected", true);
	$("mic").textContent = "Stop";
	$("mic").classList.add("live");
}

function teardown() {
	micStream?.getTracks().forEach((t) => t.stop());
	micCtx?.close();
	micCtx = micStream = null;
	stopPlayback();
	$("mic").textContent = "Connect & talk";
	$("mic").classList.remove("live");
}

$("mic").onclick = async () => {
	if (ws && ws.readyState === WebSocket.OPEN) { ws.close(); ws = null; return; }
	$("mic").disabled = true;
	try { await connect(); } catch (err) {
		setStatus(`failed: ${err.message ?? err}`, false);
		teardown();
	} finally { $("mic").disabled = false; }
};

fetch("/dev/config").then((r) => r.json()).then((c) => {
	$("m-llm").textContent = c.ollama_model;
	$("m-stt").textContent = c.whisper_model;
	$("m-tts").textContent = c.piper_voice;
	if (!c.voice_enabled) {
		$("mic").disabled = true;
		$("mic").title = "Set BT_VOICE=1 to enable the voice pipeline";
		setStatus("voice disabled", false);
	}
});
