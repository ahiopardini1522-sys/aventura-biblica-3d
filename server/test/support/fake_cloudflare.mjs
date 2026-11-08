// Dobles de prueba de lo que Cloudflare da a un Durable Object: WebSocket, almacenamiento y contexto.

export class FakeWebSocket {
  constructor() {
    this.sent = [];
    this.closed = null; // { code, reason } cuando se cerró
    this.attachment = null;
  }

  send(text) {
    if (this.closed) throw new Error("la conexión está cerrada");
    this.sent.push(text);
  }

  close(code, reason) {
    if (this.closed) throw new Error("ya estaba cerrada");
    this.closed = { code, reason };
  }

  serializeAttachment(value) {
    if (this.closed) throw new Error("la conexión está cerrada");
    this.attachment = structuredClone(value);
  }

  deserializeAttachment() {
    return this.attachment === null ? null : structuredClone(this.attachment);
  }

  /** Mensajes enviados, ya convertidos de JSON (el texto "pong" queda como texto). */
  messages() {
    return this.sent.map((text) => (text === "pong" ? text : JSON.parse(text)));
  }
}

export class FakeStorage {
  constructor() {
    this.data = new Map();
    this.alarm = null;
    this.puts = 0;
  }

  async get(key) {
    return structuredClone(this.data.get(key));
  }

  async put(key, value) {
    this.puts += 1;
    this.data.set(key, structuredClone(value));
  }

  async getAlarm() {
    return this.alarm;
  }

  async setAlarm(time) {
    this.alarm = time;
  }
}

export class FakeContext {
  constructor() {
    this.storage = new FakeStorage();
    this.accepted = [];
    this.autoResponse = null;
    this.pending = [];
  }

  acceptWebSocket(ws) {
    this.accepted.push(ws);
  }

  getWebSockets() {
    return this.accepted.filter((ws) => !ws.closed);
  }

  setWebSocketAutoResponse(pair) {
    this.autoResponse = pair;
  }

  blockConcurrencyWhile(fn) {
    const promise = fn();
    this.pending.push(promise);
    return promise;
  }

  /** Espera a que termine la inicialización del Hub (lo que en Cloudflare hace blockConcurrencyWhile). */
  async ready() {
    await Promise.all(this.pending);
    this.pending = [];
  }
}

/** Instala los globales de Cloudflare que usa worker.js. */
export function installCloudflareGlobals() {
  globalThis.WebSocketRequestResponsePair = class {
    constructor(request, response) {
      this.request = request;
      this.response = response;
    }
  };
  globalThis.WebSocketPair = class {
    constructor() {
      this[0] = new FakeWebSocket();
      this[1] = new FakeWebSocket();
    }
  };
  // Node no deja crear una Response con estado 101; Cloudflare sí.
  const RealResponse = globalThis.Response;
  globalThis.Response = class extends RealResponse {
    constructor(body, init) {
      if (init && init.status === 101) {
        super(null, { status: 200 });
        Object.defineProperty(this, "status", { value: 101 });
        this.webSocket = init.webSocket;
      } else {
        super(body, init);
      }
    }
  };
}
