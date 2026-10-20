class Capture extends AudioWorkletProcessor {
  constructor() { super(); this.samples = []; }
  process(inputs) {
    const input = inputs[0]?.[0];
    if (!input) return true;
    for (const value of input) this.samples.push(Math.max(-1, Math.min(1, value)) * 32767);
    if (this.samples.length >= 512) {
      const pcm = new Int16Array(this.samples);
      this.port.postMessage(pcm.buffer, [pcm.buffer]);
      this.samples = [];
    }
    return true;
  }
}
registerProcessor('capture', Capture);
