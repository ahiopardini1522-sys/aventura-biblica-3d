// Pruebas del "pegamento" con Cloudflare (src/worker.js) usando dobles de prueba: se comprueba
// que los efectos de hub_core se ejecutan bien, que el estado se guarda y que el Hub se
// reconstruye correctamente al despertar de la hibernación.

import assert from "node:assert/strict";
import { register } from "node:module";
import { after, test } from "node:test";

import { FakeContext, installCloudflareGlobals } from "./support/fake_cloudflare.mjs";

register("./support/cloudflare_hooks.mjs", import.meta.url);
installCloudflareGlobals();

const { default: worker, Hub } = await import("../src/worker.js");
const { CLOSE, LIMITS, PROTOCOL_VERSION } = await import("../src/protocol.js");

const CLIENT_A = "cliente-aaaaaaaaaaaaaaaa";
const CLIENT_B = "cliente-bbbbbbbbbbbbbbbb";
const hello = (client, extra = {}) => JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, client, name: "Ana", ...extra });

const realNow = Date.now;
let fakeNow = 5_000_000;
Date.now = () => fakeNow;
after(() => {
  Date.now = realNow;
});

async function newHub(ctx = new FakeContext()) {
  const hub = new Hub(ctx, {});
  await ctx.ready();
  return { hub, ctx };
}

async function connect(hub, ip = "9.9.9.9") {
  const request = new Request("https://juego.example/ws", { headers: { Upgrade: "websocket", "CF-Connecting-IP": ip } });
  const response = await hub.fetch(request);
  assert.equal(response.status, 101);
  assert.ok(response.webSocket, "la respuesta lleva el WebSocket del cliente");
  // En Cloudflare el servidor es la segunda punta del par: el Hub guarda la que aceptó.
  return hub.ctx.accepted.at(-1);
}

test("el Worker responde /health y rechaza lo demás", async () => {
  const health = await worker.fetch(new Request("https://juego.example/health"), {});
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { ok: true, service: "aventura-biblica-online", server: "0.1.0", protocol: PROTOCOL_VERSION });
  assert.equal((await worker.fetch(new Request("https://juego.example/"), {})).status, 200);
  assert.equal((await worker.fetch(new Request("https://juego.example/otra-cosa"), {})).status, 404);
  assert.equal((await worker.fetch(new Request("https://juego.example/ws"), {})).status, 426, "sin Upgrade no se pasa al Hub");
});

test("el Worker reenvía /ws al Hub con la petición original", async () => {
  const calls = [];
  const env = {
    HUB: {
      idFromName: (name) => `id:${name}`,
      get: (id) => ({ fetch: async (request) => (calls.push([id, request.url]), new Response("reenviado")) }),
    },
  };
  const response = await worker.fetch(new Request("https://juego.example/ws", { headers: { Upgrade: "WebSocket" } }), env);
  assert.equal(await response.text(), "reenviado");
  assert.deepEqual(calls, [["id:principal", "https://juego.example/ws"]]);
});

test("el Hub configura la respuesta automática de ping", async () => {
  const { ctx } = await newHub();
  assert.equal(ctx.autoResponse.request, "ping");
  assert.equal(ctx.autoResponse.response, "pong");
});

test("saludo completo: welcome al cliente, sesión guardada y datos pegados al WebSocket", async () => {
  const { hub, ctx } = await newHub();
  const ws = await connect(hub);
  assert.equal(ws.attachment.helloDone, false);
  assert.equal(ctx.storage.alarm, fakeNow + LIMITS.HANDSHAKE_TIMEOUT_MS, "se vigila que llegue el saludo");

  await hub.webSocketMessage(ws, hello(CLIENT_A));
  const [welcome] = ws.messages();
  assert.equal(welcome.t, "welcome");
  assert.equal(welcome.resumed, false);
  assert.equal(ws.attachment.helloDone, true);
  assert.equal(ws.attachment.clientId, CLIENT_A);
  assert.equal(ctx.storage.data.get("state").sessions.length, 1);
  assert.equal(ctx.storage.data.get("state").sessions[0][0], welcome.session);
});

test("un mensaje inválido recibe error y la conexión se cierra con el código acordado", async () => {
  const { hub } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, "no soy json");
  assert.equal(ws.messages()[0].code, "bad_message");
  assert.deepEqual(ws.closed, { code: CLOSE.BAD_MESSAGE, reason: "bad_message" });
  assert.equal(hub.core.conns.size, 0);
  assert.equal(hub.sockets.size, 0);
});

test("un mensaje binario se rechaza", async () => {
  const { hub } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, new ArrayBuffer(4));
  assert.equal(ws.messages()[0].code, "bad_message");
  assert.equal(ws.closed.code, CLOSE.BAD_MESSAGE);
});

test("mismo jugador desde otro lugar: la conexión vieja recibe bye y se cierra", async () => {
  const { hub } = await newHub();
  const vieja = await connect(hub);
  await hub.webSocketMessage(vieja, hello(CLIENT_A));
  const nueva = await connect(hub);
  await hub.webSocketMessage(nueva, hello(CLIENT_A, { resume: vieja.messages()[0].session }));

  assert.deepEqual(vieja.messages()[1], { t: "bye", reason: "replaced" });
  assert.deepEqual(vieja.closed, { code: CLOSE.REPLACED, reason: "replaced" });
  assert.equal(nueva.messages()[0].resumed, true);
  assert.equal(nueva.closed, null);

  // El cierre tardío de la conexión vieja no debe afectar a la nueva.
  await hub.webSocketClose(vieja, CLOSE.REPLACED, "replaced");
  assert.equal(hub.core.onlineCount(), 1);
  assert.equal(hub.core.sessions.get(nueva.messages()[0].session).expires, null);
});

test("demasiadas conexiones desde una dirección: se rechaza con aviso", async () => {
  const { hub } = await newHub();
  const abiertas = [];
  for (let i = 0; i < LIMITS.MAX_PER_IP; i += 1) abiertas.push(await connect(hub, "7.7.7.7"));
  const de_mas = await connect(hub, "7.7.7.7");
  assert.equal(de_mas.messages()[0].code, "too_many_connections");
  assert.equal(de_mas.closed.code, CLOSE.TOO_MANY);
  assert.ok(abiertas.every((ws) => ws.closed === null));
  assert.equal(hub.core.conns.size, LIMITS.MAX_PER_IP);
});

test("al cortarse la conexión, la sesión empieza a vencer y se guarda", async () => {
  const { hub, ctx } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, hello(CLIENT_A));
  const putsBefore = ctx.storage.puts;

  await hub.webSocketClose(ws, 1005, "");
  assert.ok(ctx.storage.puts > putsBefore, "se guardó el cambio");
  const [, session] = ctx.storage.data.get("state").sessions[0];
  assert.equal(session.expires, fakeNow + LIMITS.SESSION_TTL_MS);
  assert.ok(ctx.storage.alarm !== null && ctx.storage.alarm <= session.expires, "hay una alarma programada para limpiar");
  assert.equal(ws.closed.code, 1000, "el código reservado 1005 se responde con 1000");

  // Cuando suena la alarma más temprana (la del saludo) se reprograma para la limpieza de la sesión.
  fakeNow = ctx.storage.alarm;
  await hub.alarm();
  assert.equal(ctx.storage.alarm, session.expires);
});

test("el cierre sin saludo previo no rompe nada", async () => {
  const { hub } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketClose(ws, 1001, "");
  await hub.webSocketError(ws);
  assert.equal(hub.core.conns.size, 0);
});

test("hibernación: un Hub nuevo recupera las conexiones y las sesiones", async () => {
  const { hub, ctx } = await newHub();
  const ana = await connect(hub);
  await hub.webSocketMessage(ana, hello(CLIENT_A));
  const beto = await connect(hub);
  await hub.webSocketMessage(beto, hello(CLIENT_B, { name: "Beto" }));
  const sinSaludo = await connect(hub);

  // El Hub se duerme (se pierde la memoria) y despierta con el mismo almacenamiento y los mismos WebSockets.
  const despierto = new Hub(ctx, {});
  await ctx.ready();
  assert.equal(despierto.core.onlineCount(), 2);
  assert.equal(despierto.core.conns.size, 3);

  await despierto.webSocketMessage(ana, JSON.stringify({ t: "stats" }));
  assert.deepEqual(ana.messages().at(-1), { t: "stats", online: 2 });

  // Beto se desconecta y reanuda con su código.
  await despierto.webSocketClose(beto, 1006, "");
  const nuevo = await connect(despierto, "8.8.8.8");
  await despierto.webSocketMessage(nuevo, hello(CLIENT_B, { name: "Beto", resume: beto.messages()[0].session }));
  assert.equal(nuevo.messages()[0].resumed, true);

  // Quien no saludó sigue sujeto al tiempo límite.
  fakeNow += LIMITS.HANDSHAKE_TIMEOUT_MS;
  await despierto.alarm();
  assert.equal(sinSaludo.messages()[0].code, "handshake_timeout");
  assert.equal(sinSaludo.closed.code, CLOSE.HANDSHAKE_TIMEOUT);
  assert.equal(ana.closed, null);
});

test("hibernación: una conexión cerrada mientras dormía deja la sesión para limpiar", async () => {
  const { hub, ctx } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, hello(CLIENT_A));

  ws.closed = { code: 1006, reason: "" }; // se cortó mientras el Hub dormía: ya no figura en getWebSockets()
  const despierto = new Hub(ctx, {});
  await ctx.ready();
  assert.equal(despierto.core.onlineCount(), 0);
  assert.ok(ctx.storage.alarm !== null && ctx.storage.alarm <= fakeNow, "se programó una revisión inmediata");

  await despierto.alarm();
  const [, session] = ctx.storage.data.get("state").sessions[0];
  assert.equal(session.expires, fakeNow + LIMITS.SESSION_TTL_MS, "la sesión huérfana empieza a vencer");
});

test("alarma: borra las sesiones vencidas y no deja alarmas innecesarias", async () => {
  const { hub, ctx } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, hello(CLIENT_A));
  await hub.webSocketClose(ws, 1000, "");

  fakeNow += LIMITS.SESSION_TTL_MS + 1;
  await hub.alarm();
  assert.equal(ctx.storage.data.get("state").sessions.length, 0);
  assert.equal(hub.core.nextWake(), null);
});

test("un WebSocket desconocido que escribe se cierra sin afectar a los demás", async () => {
  const { hub } = await newHub();
  const { FakeWebSocket } = await import("./support/fake_cloudflare.mjs");
  const intruso = new FakeWebSocket();
  await hub.webSocketMessage(intruso, hello(CLIENT_A));
  assert.deepEqual(intruso.closed, { code: 4002, reason: "unknown_connection" });
});

test("stats y bye pasan por el Hub", async () => {
  const { hub } = await newHub();
  const ws = await connect(hub);
  await hub.webSocketMessage(ws, hello(CLIENT_A));
  await hub.webSocketMessage(ws, JSON.stringify({ t: "stats" }));
  assert.deepEqual(ws.messages().at(-1), { t: "stats", online: 1 });
  await hub.webSocketMessage(ws, JSON.stringify({ t: "bye" }));
  assert.deepEqual(ws.closed, { code: 1000, reason: "bye" });
  assert.equal(hub.core.sessions.size, 0);
});
