export class VoiceConnection {
  constructor(url, onMessage, onState) {
    this.url = url;
    this.onMessage = onMessage;
    this.onState = onState;
    this.wanted = false;
    this.socket = null;
    this.attempt = 0;
  }
  start() {
    this.wanted = true;
    this.open();
  }
  open() {
    if (!this.wanted) return;
    const socket = new WebSocket(this.url());
    this.socket = socket;
    this.onState('connecting');
    let timedOut = false;
    this.timer = setTimeout(() => { timedOut = true; socket.close(); }, 30000);
    socket.onmessage = event => {
      if (this.socket !== socket) return;
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (message.type === 'ready') {
        clearTimeout(this.timer);
        this.attempt = 0;
        this.onState('ready');
      }
      this.onMessage(message);
    };
    socket.onclose = event => {
      if (this.socket !== socket) return;
      clearTimeout(this.timer);
      this.socket = null;
      // After a drop the server may still hold the old session briefly, so busy (1013) retries.
      const busyAfterDrop = event.code === 1013 && this.attempt > 0;
      if (!this.wanted || (!timedOut && !busyAfterDrop && [1000, 1008, 1011, 1013].includes(event.code))) {
        this.wanted = false;
        this.onState('disconnected', event.reason);
        return;
      }
      this.onState('reconnecting');
      this.timer = setTimeout(() => this.open(), Math.min(1000 * 2 ** this.attempt++, 30000));
    };
    socket.onerror = () => {};
  }
  send(data) {
    if (this.socket?.readyState === 1) this.socket.send(data);
  }
  stop() {
    this.wanted = false;
    clearTimeout(this.timer);
    const socket = this.socket;
    this.socket = null;
    socket?.close();
    this.onState('disconnected');
  }
}
