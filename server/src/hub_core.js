// Lógica pura del servidor en línea (sin nada de Cloudflare): conexiones, saludo, sesiones y límites.
//
// Cada método recibe lo que pasó (se abrió una conexión, llegó un mensaje, se cerró) y devuelve
// "efectos": mensajes que hay que enviar y conexiones que hay que cerrar. Quien la use (el Durable
// Object de Cloudflare en producción, las pruebas de Node en CI) solo tiene que ejecutar esos efectos.
// Así la misma lógica se prueba en Node, sin red, y es la que corre en el servidor real.
//
//   efectos = { out: [{ conn, text }], close: [{ conn, code, reason }] }
//
// Las fases siguientes (salas, emparejamiento, turnos) se agregan aquí como nuevos tipos de mensaje.

import {
  CLOSE,
  LIMITS,
  PROTOCOL_VERSION,
  SERVER_VERSION,
  cleanName,
  decode,
  encode,
  isValidClientId,
  isValidSession,
} from "./protocol.js";

const DEFAULT_NAME = "Jugador";
const NORMAL_CLOSE = 1000;

function randomHex(bytes) {
  const buffer = new Uint8Array(bytes);
  globalThis.crypto.getRandomValues(buffer);
  return Array.from(buffer, (b) => b.toString(16).padStart(2, "0")).join("");
}

function newEffects() {
  return { out: [], close: [] };
}

function send(effects, conn, message) {
  effects.out.push({ conn, text: encode(message) });
}

function closeWith(effects, conn, code, reason) {
  effects.close.push({ conn, code, reason });
}

export class HubCore {
  constructor(options = {}) {
    this.now = options.now ?? (() => Date.now());
    this.randomHex = options.randomHex ?? randomHex;
    this.limits = { ...LIMITS, ...(options.limits ?? {}) };
    /** @type {Map<string, object>} conexiones abiertas, por identificador de conexión */
    this.conns = new Map();
    /** @type {Map<string, {clientId: string, name: string, expires: number|null}>} sesiones, por código */
    this.sessions = new Map();
    /** jugador (client id) -> código de su sesión */
    this.sessionByClient = new Map();
    /** jugador (client id) -> conexión que lo representa ahora */
    this.active = new Map();
    /** Verdadero cuando las sesiones cambiaron y hay que guardarlas. */
    this.dirty = false;
  }

  // ------------------------------------------------------------ Ciclo de vida de la conexión

  onOpen(connId, { ip = "" } = {}) {
    const effects = newEffects();
    const full = this.conns.size >= this.limits.MAX_CONNECTIONS;
    const crowded = ip !== "" && this.#countForIp(ip) >= this.limits.MAX_PER_IP;
    if (full || crowded) {
      send(effects, connId, { t: "error", code: "too_many_connections", msg: "Demasiadas conexiones; prueba en un momento." });
      closeWith(effects, connId, CLOSE.TOO_MANY, "too_many_connections");
      return effects;
    }
    const now = this.now();
    this.conns.set(connId, this.#newConn(connId, ip, now));
    return effects;
  }

  onMessage(connId, data) {
    const effects = newEffects();
    const conn = this.conns.get(connId);
    if (!conn) return effects;

    if (typeof data !== "string") {
      this.#reject(effects, conn, "bad_message", "Solo se aceptan mensajes de texto.");
      return effects;
    }
    if (data.length > this.limits.MAX_MESSAGE_CHARS) {
      this.#reject(effects, conn, "too_big", "Mensaje demasiado grande.");
      return effects;
    }
    if (!this.#takeToken(conn)) {
      send(effects, connId, { t: "error", code: "rate_limited", msg: "Demasiados mensajes seguidos." });
      this.#drop(effects, conn, CLOSE.RATE_LIMITED, "rate_limited");
      return effects;
    }
    if (data === "ping") {
      effects.out.push({ conn: connId, text: "pong" });
      return effects;
    }

    const message = decode(data);
    if (message === null) {
      this.#invalid(effects, conn, "bad_message", "El mensaje no es un objeto JSON con tipo.");
      return effects;
    }
    switch (message.t) {
      case "hello":
        this.#hello(effects, conn, message);
        break;
      case "ping":
        send(effects, connId, { t: "pong", now: this.now() });
        break;
      case "bye":
        this.#bye(effects, conn);
        break;
      case "stats":
        if (!conn.helloDone) {
          this.#invalid(effects, conn, "hello_required", 'Primero hay que saludar con "hello".');
        } else {
          send(effects, connId, { t: "stats", online: this.onlineCount() });
        }
        break;
      default:
        if (!conn.helloDone) {
          this.#invalid(effects, conn, "hello_required", 'Primero hay que saludar con "hello".');
        } else {
          this.#invalid(effects, conn, "unknown_type", `Tipo de mensaje desconocido: ${message.t}`);
        }
    }
    return effects;
  }

  /** La conexión se cortó (por el cliente, por la red o porque el servidor la cerró). Es idempotente. */
  onClose(connId) {
    const effects = newEffects();
    const conn = this.conns.get(connId);
    if (!conn) return effects;
    this.conns.delete(connId);
    this.#release(conn);
    return effects;
  }

  /**
   * Revisión periódica (la dispara una alarma): cierra las conexiones que no saludaron a tiempo,
   * deja correr el reloj de las sesiones huérfanas y borra las sesiones vencidas.
   */
  sweep() {
    const effects = newEffects();
    const now = this.now();
    for (const conn of [...this.conns.values()]) {
      if (!conn.helloDone && now - conn.openedAt >= this.limits.HANDSHAKE_TIMEOUT_MS) {
        send(effects, conn.id, { t: "error", code: "handshake_timeout", msg: "No llegó el saludo a tiempo." });
        this.#drop(effects, conn, CLOSE.HANDSHAKE_TIMEOUT, "handshake_timeout");
      }
    }
    for (const [token, session] of [...this.sessions]) {
      if (session.expires === null && !this.active.has(session.clientId)) {
        // Sesión de alguien que ya no está conectado y cuyo cierre no se anotó (por ejemplo, tras un reinicio).
        session.expires = now + this.limits.SESSION_TTL_MS;
        this.dirty = true;
      }
      if (session.expires !== null && session.expires <= now) this.#dropSession(token);
    }
    return effects;
  }

  /** Cuándo hace falta volver a llamar a sweep() (milisegundos desde 1970), o null si no hace falta. */
  nextWake() {
    let next = null;
    const consider = (time) => {
      if (next === null || time < next) next = time;
    };
    for (const conn of this.conns.values()) {
      if (!conn.helloDone) consider(conn.openedAt + this.limits.HANDSHAKE_TIMEOUT_MS);
    }
    for (const session of this.sessions.values()) {
      if (session.expires !== null) consider(session.expires);
      else if (!this.active.has(session.clientId)) consider(this.now());
    }
    return next;
  }

  onlineCount() {
    let count = 0;
    for (const conn of this.conns.values()) if (conn.helloDone) count += 1;
    return count;
  }

  // ------------------------------------------------------------ Guardado (el Durable Object se duerme)

  /** Sesiones en un objeto simple, para guardarlas en el almacenamiento del servidor. */
  exportState() {
    return {
      sessions: [...this.sessions].map(([token, s]) => [token, { clientId: s.clientId, name: s.name, expires: s.expires }]),
    };
  }

  importState(state) {
    this.sessions.clear();
    this.sessionByClient.clear();
    const list = Array.isArray(state?.sessions) ? state.sessions : [];
    for (const entry of list) {
      if (!Array.isArray(entry)) continue;
      const [token, s] = entry;
      if (!isValidSession(token) || !isValidClientId(s?.clientId)) continue;
      const expires = Number.isFinite(s.expires) ? s.expires : null;
      this.sessions.set(token, { clientId: s.clientId, name: String(s.name ?? ""), expires });
      this.sessionByClient.set(s.clientId, token);
    }
    this.dirty = false;
  }

  /** Datos de una conexión que sobreviven al sueño del servidor (se guardan junto al WebSocket). */
  exportConn(connId) {
    const conn = this.conns.get(connId);
    if (!conn) return null;
    return {
      id: conn.id,
      ip: conn.ip,
      openedAt: conn.openedAt,
      helloAt: conn.helloAt,
      helloDone: conn.helloDone,
      clientId: conn.clientId,
      name: conn.name,
      session: conn.session,
    };
  }

  /** Vuelve a registrar una conexión que ya existía antes de que el servidor se durmiera. */
  restoreConn(saved) {
    if (!saved || typeof saved.id !== "string" || saved.id === "" || this.conns.has(saved.id)) return false;
    const now = this.now();
    const conn = this.#newConn(saved.id, String(saved.ip ?? ""), Number.isFinite(saved.openedAt) ? saved.openedAt : now);
    conn.helloDone = Boolean(saved.helloDone) && isValidClientId(saved.clientId);
    conn.helloAt = Number.isFinite(saved.helloAt) ? saved.helloAt : 0;
    conn.clientId = conn.helloDone ? saved.clientId : "";
    conn.name = String(saved.name ?? "");
    conn.session = String(saved.session ?? "");
    this.conns.set(conn.id, conn);
    // Si por algún motivo ya hay otra conexión activa de ese jugador, la que ya estaba gana.
    if (conn.helloDone && !this.active.has(conn.clientId)) this.active.set(conn.clientId, conn.id);
    return true;
  }

  // ------------------------------------------------------------ Internos

  #newConn(id, ip, openedAt) {
    return {
      id,
      ip,
      openedAt,
      helloDone: false,
      helloAt: 0,
      clientId: "",
      name: "",
      session: "",
      strikes: 0,
      tokens: this.limits.RATE_CAPACITY,
      refilledAt: this.now(),
    };
  }

  #hello(effects, conn, message) {
    if (conn.helloDone) {
      this.#invalid(effects, conn, "already_hello", "Ya saludaste.");
      return;
    }
    if (!Number.isInteger(message.v)) {
      this.#invalid(effects, conn, "bad_message", "Falta la versión del protocolo (v).");
      return;
    }
    if (message.v !== PROTOCOL_VERSION) {
      send(effects, conn.id, {
        t: "error",
        code: "bad_version",
        supported: PROTOCOL_VERSION,
        msg: "Tu versión del juego no coincide con la del servidor. Actualiza la app.",
      });
      this.#drop(effects, conn, CLOSE.BAD_VERSION, "bad_version");
      return;
    }
    if (!isValidClientId(message.client)) {
      this.#invalid(effects, conn, "bad_client", "Identificador de jugador no válido.");
      return;
    }

    const now = this.now();
    const name = cleanName(message.name) || DEFAULT_NAME;
    const clientId = message.client;

    // Si el mismo jugador ya tenía otra conexión abierta, la nueva la reemplaza.
    const previousId = this.active.get(clientId);
    if (previousId !== undefined && previousId !== conn.id) {
      const previous = this.conns.get(previousId);
      send(effects, previousId, { t: "bye", reason: "replaced" });
      closeWith(effects, previousId, CLOSE.REPLACED, "replaced");
      this.conns.delete(previousId);
      this.active.delete(clientId);
      if (previous) previous.helloDone = false;
    }

    // Reanudar la sesión anterior si el código es válido, es de este jugador y no venció.
    let token = isValidSession(message.resume) ? message.resume : "";
    let session = token ? this.sessions.get(token) : undefined;
    let resumed = false;
    if (session && session.clientId === clientId && (session.expires === null || session.expires > now)) {
      resumed = true;
    } else {
      const old = this.sessionByClient.get(clientId);
      if (old) this.#dropSession(old);
      this.#makeRoomForSession(now);
      token = this.randomHex(16);
      session = { clientId, name, expires: null };
      this.sessions.set(token, session);
      this.sessionByClient.set(clientId, token);
    }
    session.name = name;
    session.expires = null;
    this.dirty = true;

    conn.helloDone = true;
    conn.helloAt = now;
    conn.clientId = clientId;
    conn.name = name;
    conn.session = token;
    this.active.set(clientId, conn.id);

    send(effects, conn.id, {
      t: "welcome",
      v: PROTOCOL_VERSION,
      session: token,
      resumed,
      server: SERVER_VERSION,
      now,
      online: this.onlineCount(),
      you: { client: clientId, name },
    });
  }

  /** Despedida voluntaria: no hace falta guardar la sesión para una reconexión. */
  #bye(effects, conn) {
    if (conn.helloDone) {
      const token = this.sessionByClient.get(conn.clientId);
      if (token) this.#dropSession(token);
    }
    this.#drop(effects, conn, NORMAL_CLOSE, "bye");
  }

  /** Mensaje inválido: antes del saludo se corta la conexión; después se toleran unos pocos. */
  #invalid(effects, conn, code, text) {
    send(effects, conn.id, { t: "error", code, msg: text });
    if (!conn.helloDone) {
      this.#drop(effects, conn, CLOSE.BAD_MESSAGE, code);
      return;
    }
    conn.strikes += 1;
    if (conn.strikes >= this.limits.MAX_STRIKES) {
      this.#drop(effects, conn, CLOSE.BAD_MESSAGE, "too_many_invalid_messages");
    }
  }

  /** Error grave (mensaje enorme, binario): se avisa y se corta de inmediato. */
  #reject(effects, conn, code, text) {
    send(effects, conn.id, { t: "error", code, msg: text });
    this.#drop(effects, conn, CLOSE.BAD_MESSAGE, code);
  }

  /** Cierra la conexión y la da de baja ahora mismo (el cierre real lo hace quien ejecuta los efectos). */
  #drop(effects, conn, code, reason) {
    closeWith(effects, conn.id, code, reason);
    if (this.conns.get(conn.id) === conn) {
      this.conns.delete(conn.id);
      this.#release(conn);
    }
  }

  /** La conexión deja de representar al jugador; su sesión queda esperando una posible reconexión. */
  #release(conn) {
    if (!conn.helloDone || this.active.get(conn.clientId) !== conn.id) return;
    this.active.delete(conn.clientId);
    const token = this.sessionByClient.get(conn.clientId);
    const session = token ? this.sessions.get(token) : undefined;
    if (session) {
      session.expires = this.now() + this.limits.SESSION_TTL_MS;
      this.dirty = true;
    }
  }

  #dropSession(token) {
    const session = this.sessions.get(token);
    if (!session) return;
    this.sessions.delete(token);
    if (this.sessionByClient.get(session.clientId) === token) this.sessionByClient.delete(session.clientId);
    this.dirty = true;
  }

  /** Si ya hay demasiadas sesiones guardadas, libera las vencidas y luego las que antes iban a vencer. */
  #makeRoomForSession(now) {
    if (this.sessions.size < this.limits.MAX_SESSIONS) return;
    for (const [token, session] of [...this.sessions]) {
      if (session.expires !== null && session.expires <= now) this.#dropSession(token);
    }
    while (this.sessions.size >= this.limits.MAX_SESSIONS) {
      let oldestToken = null;
      let oldestExpires = Infinity;
      for (const [token, session] of this.sessions) {
        if (session.expires !== null && session.expires < oldestExpires) {
          oldestToken = token;
          oldestExpires = session.expires;
        }
      }
      if (oldestToken === null) break; // todas pertenecen a jugadores conectados
      this.#dropSession(oldestToken);
    }
  }

  #takeToken(conn) {
    const now = this.now();
    const elapsedSeconds = Math.max(0, now - conn.refilledAt) / 1000;
    conn.tokens = Math.min(this.limits.RATE_CAPACITY, conn.tokens + elapsedSeconds * this.limits.RATE_REFILL_PER_SECOND);
    conn.refilledAt = now;
    if (conn.tokens < 1) return false;
    conn.tokens -= 1;
    return true;
  }

  #countForIp(ip) {
    let count = 0;
    for (const conn of this.conns.values()) if (conn.ip === ip) count += 1;
    return count;
  }
}
