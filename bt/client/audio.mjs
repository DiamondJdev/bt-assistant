export class Playback {
  constructor(context) {
    this.context = context;
    this.sources = new Set();
    this.playAt = 0;
    this.onchange = null;
  }
  get playing() { return this.sources.size > 0; }
  play(pcm, rate) {
    const bytes = Uint8Array.from(atob(pcm), c => c.charCodeAt(0));
    const samples = new DataView(bytes.buffer);
    const buffer = this.context.createBuffer(1, bytes.length / 2, rate);
    const channel = buffer.getChannelData(0);
    for (let i = 0; i < channel.length; i++) channel[i] = samples.getInt16(i * 2, true) / 32768;
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.context.destination);
    this.sources.add(source);
    source.onended = () => { this.sources.delete(source); this.onchange?.(this.playing); };
    this.playAt = Math.max(this.playAt, this.context.currentTime);
    source.start(this.playAt);
    this.playAt += buffer.duration;
    this.onchange?.(true);
  }
  stop() {
    for (const source of this.sources) source.stop();
    this.sources.clear();
    this.playAt = 0;
    this.onchange?.(false);
  }
}

export function audioMessage(buffer) {
  let binary = '';
  for (const byte of new Uint8Array(buffer)) binary += String.fromCharCode(byte);
  return JSON.stringify({ type: 'audio', pcm: btoa(binary), sampleRate: 16000, channels: 1 });
}

// RMS of one 16-bit capture chunk, scaled to 0..1 for the level meter.
export function level(buffer) {
  const samples = new Int16Array(buffer);
  let sum = 0;
  for (const value of samples) sum += value * value;
  return Math.min(1, Math.sqrt(sum / (samples.length || 1)) / 8000);
}
