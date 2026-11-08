// Servidor en línea de Aventura Bíblica 3D para Cloudflare Workers (plan gratuito).
//
// Este archivo es solo el "pegamento" con Cloudflare. Toda la lógica (saludo, sesiones, límites)
// está en hub_core.js, que se prueba aparte con Node. Aquí:
//   - El Worker responde /health y pasa las conexiones WebSocket (/ws) al Durable Object "Hub".
//   - El Hub usa la API de hibernación de WebSocket: mientras nadie escribe, Cloudflare lo saca de
//     memoria sin cortar las conexiones, así no se gasta cuota. Al despertar, se reconstruye el
//     estado desde el almacenamiento (sesiones) y desde los datos pegados a cada WebSocket.
//   - El texto "ping" lo contesta "pong" el propio Cloudflare, sin despertar al Hub.

import { DurableObject } from "cloudflare:workers";

import { HubCore } from "./hub_core.js";
import { PROTOCOL_VERSION, SERVER_VERSION } from "./protocol.js";

const HUB_NAME = "principal"; // Un solo Hub por ahora; las salas llegan en la fase 4.2.
const STATE_KEY = "state";
/** Una alarma nunca se programa para "ahora mismo": se deja este margen (ms) para no repetirla en bucle. */
const MIN_ALARM_GAP_MS = 250;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "access-control-allow-origin": "*",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** Solo se pueden enviar los códigos 1000 y 3000-4999; cualquier otro (1005, 1006...) se cambia por 1000. */
function safeClose(ws, code, reason) {
  const valid = code === 1000 || (code >= 3000 && code <= 4999);
  try {
    ws.close(valid ? code : 1000, String(reason ?? "").slice(0, 100));
  } catch {
    // La conexión ya estaba cerrada.
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        ok: true,
        service: "aventura-biblica-online",
        server: SERVER_VERSION,
        protocol: PROTOCOL_VERSION,
      });
    }
    if (url.pathname === "/ws") {
      if ((request.headers.get("Upgrade") ?? "").toLowerCase() !== "websocket") {
        return json({ ok: false, error: "Se esperaba una conexión WebSocket (wss://)." }, 426);
      }
      const stub = env.HUB.get(env.HUB.idFromName(HUB_NAME));
      return stub.fetch(request);
    }
    return json({ ok: false, error: "No encontrado." }, 404);
  },
};

export class Hub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.core = new HubCore();
    /** identificador de conexión -> WebSocket */
    this.sockets = new Map();
    /** WebSocket -> identificador de conexión */
    this.ids = new Map();
    /** Hora de la alarma programada; undefined = todavía no se consultó. */
    this.alarmAt = undefined;

    // Contesta "ping" con "pong" sin despertar al Hub.
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));

    this.ctx.blockConcurrencyWhile(async () => {
      this.core.importState(await this.ctx.storage.get(STATE_KEY));
      for (const ws of this.ctx.getWebSockets()) {
        const saved = ws.deserializeAttachment();
        if (saved && this.core.restoreConn(saved)) this.#track(saved.id, ws);
      }
      await this.#schedule();
    });
  }

  async fetch(request) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const id = crypto.randomUUID();
    const ip = request.headers.get("CF-Connecting-IP") ?? "";

    this.ctx.acceptWebSocket(server);
    this.#track(id, server);
    const effects = this.core.onOpen(id, { ip });
    const saved = this.core.exportConn(id);
    if (saved) server.serializeAttachment(saved);
    this.#apply(effects);
    await this.#persist();

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    const id = this.#idOf(ws);
    if (id === null) {
      safeClose(ws, 4002, "unknown_connection");
      return;
    }
    this.#apply(this.core.onMessage(id, message));
    this.#saveAttachment(id, ws);
    await this.#persist();
  }

  async webSocketClose(ws, code, reason) {
    this.#forget(ws);
    safeClose(ws, code, "closing");
    await this.#persist();
  }

  async webSocketError(ws) {
    this.#forget(ws);
    await this.#persist();
  }

  async alarm() {
    this.alarmAt = null;
    const effects = this.core.sweep();
    console.log(`[hub] alarma: conexiones=${this.core.conns.size} cierres=${effects.close.length} sesiones=${this.core.sessions.size}`);
    this.#apply(effects);
    await this.#persist();
  }

  // ------------------------------------------------------------ Internos

  #track(id, ws) {
    this.sockets.set(id, ws);
    this.ids.set(ws, id);
  }

  #untrack(id) {
    const ws = this.sockets.get(id);
    this.sockets.delete(id);
    if (ws) this.ids.delete(ws);
    return ws;
  }

  #idOf(ws) {
    const known = this.ids.get(ws);
    if (known !== undefined) return known;
    try {
      const saved = ws.deserializeAttachment();
      if (saved && typeof saved.id === "string" && this.core.conns.has(saved.id)) {
        this.#track(saved.id, ws);
        return saved.id;
      }
    } catch {
      // Sin datos pegados: no es una conexión que conozcamos.
    }
    return null;
  }

  /** La conexión se cerró (la cortó el cliente o la red): se da de baja. */
  #forget(ws) {
    const id = this.ids.get(ws);
    if (id === undefined) return;
    this.#untrack(id);
    this.core.onClose(id);
  }

  #saveAttachment(id, ws) {
    const saved = this.core.exportConn(id);
    if (!saved) return;
    try {
      ws.serializeAttachment(saved);
    } catch {
      // La conexión se cerró durante este mensaje.
    }
  }

  /** Ejecuta lo que decidió hub_core: primero envía los mensajes y después cierra las conexiones. */
  #apply(effects) {
    for (const { conn, text } of effects.out) {
      const ws = this.sockets.get(conn);
      if (!ws) continue;
      try {
        ws.send(text);
      } catch {
        // El cliente ya no está; el cierre llegará por webSocketClose.
      }
    }
    for (const { conn, code, reason } of effects.close) {
      const ws = this.#untrack(conn);
      this.core.onClose(conn);
      if (ws) safeClose(ws, code, reason);
    }
  }

  /** Guarda las sesiones si cambiaron y programa la próxima revisión. */
  async #persist() {
    if (this.core.dirty) {
      this.core.dirty = false;
      await this.ctx.storage.put(STATE_KEY, this.core.exportState());
    }
    await this.#schedule();
  }

  /**
   * Programa una alarma para revisar saludos atrasados y sesiones vencidas.
   *
   * Nunca se pide una hora igual o anterior a "ahora + MIN_ALARM_GAP_MS": si la revisión ya toca,
   * se hace en un instante, y así tampoco se vuelve a pedir la misma hora de la alarma que acaba de
   * sonar (Cloudflare puede descartar esa petición y la revisión se perdería).
   */
  async #schedule() {
    const wake = this.core.nextWake();
    if (wake === null) return;
    const target = Math.max(wake, this.core.now() + MIN_ALARM_GAP_MS);
    if (this.alarmAt === undefined) this.alarmAt = await this.ctx.storage.getAlarm();
    if (this.alarmAt === null || this.alarmAt > target) {
      await this.ctx.storage.setAlarm(target);
      console.log(`[hub] alarma programada en ${target - this.core.now()} ms`);
      this.alarmAt = target;
    }
  }
}
