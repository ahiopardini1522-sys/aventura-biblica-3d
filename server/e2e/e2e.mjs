// Pruebas de extremo a extremo: se conectan por WebSocket a un servidor REAL (el de `wrangler dev`
// en CI, el recién desplegado en Cloudflare o el servidor local de e2e/local_server.mjs) y
// comprueban el protocolo completo: saludo, ping, estadísticas, reanudar sesión, reemplazo,
// errores, límites, tiempo de espera del saludo y despedida.
//
//   node e2e/e2e.mjs http://127.0.0.1:8787
//   SERVER_URL=https://aventura-biblica-online.ejemplo.workers.dev node e2e/e2e.mjs
//
// Usa el WebSocket incluido en Node 22; no necesita instalar nada.

import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

const rawUrl = process.argv[2] ?? process.env.SERVER_URL;
if (!rawUrl) {
  console.error("Falta la dirección del servidor. Uso: node e2e/e2e.mjs https://servidor.ejemplo.workers.dev");
  process.exit(2);
}
const httpUrl = rawUrl.replace(/^ws/, "http").replace(/\/+$/, "").replace(/\/ws$/, "");
const wsUrl = `${httpUrl.replace(/^http/, "ws")}/ws`;
const PROTOCOL = 1;
const runId = randomBytes(6).toString("hex");
const clientId = (name) => `e2e-${runId}-${name}`.padEnd(16, "x");

const open = new Set();

function connect() {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    const inbox = [];
    const waiters = [];
    const closeWaiters = [];
    let closeInfo = null;

    const deliver = () => {
      for (const waiter of [...waiters]) {
        const index = inbox.findIndex(waiter.test);
        if (index >= 0) {
          waiters.splice(waiters.indexOf(waiter), 1);
          waiter.resolve(inbox.splice(index, 1)[0]);
        }
      }
    };

    const client = {
      socket,
      inbox,
      send: (value) => socket.send(typeof value === "string" ? value : JSON.stringify(value)),
      next: (test = () => true, ms = 8000) =>
        new Promise((done, fail) => {
          const waiter = { test, resolve: done };
          waiters.push(waiter);
          deliver();
          setTimeout(() => {
            if (waiters.includes(waiter)) {
              waiters.splice(waiters.indexOf(waiter), 1);
              fail(new Error(`no llegó el mensaje esperado en ${ms} ms (bandeja: ${JSON.stringify(inbox)})`));
            }
          }, ms);
        }),
      closed: (ms = 8000) =>
        new Promise((done, fail) => {
          if (closeInfo) return done(closeInfo);
          closeWaiters.push(done);
          setTimeout(
            () =>
              fail(
                new Error(
                  `la conexión no se cerró en ${ms} ms (estado ${socket.readyState}, recibido: ${JSON.stringify(inbox)})`,
                ),
              ),
            ms,
          );
        }),
      close: () => {
        try {
          socket.close();
        } catch {
          /* ya estaba cerrada */
        }
      },
      hello: async (name, extra = {}) => {
        client.send({ t: "hello", v: PROTOCOL, client: clientId(name), name: name.toUpperCase(), ...extra });
        return client.next((m) => m.t === "welcome" || m.t === "error");
      },
    };

    socket.addEventListener("message", (event) => {
      const text = String(event.data);
      let value = text;
      if (text !== "pong") value = JSON.parse(text);
      inbox.push(value);
      deliver();
    });
    socket.addEventListener("close", (event) => {
      closeInfo = { code: event.code, reason: event.reason };
      closeWaiters.splice(0).forEach((done) => done(closeInfo));
    });
    socket.addEventListener("error", () => reject(new Error(`no se pudo conectar a ${wsUrl}`)));
    socket.addEventListener("open", () => {
      open.add(client);
      resolve(client);
    });
  });
}

const results = [];
async function step(name, fn) {
  const started = Date.now();
  try {
    await fn();
    results.push({ name, ok: true });
    console.log(`  ok     ${name} (${Date.now() - started} ms)`);
  } catch (error) {
    results.push({ name, ok: false, error });
    console.log(`  FALLA  ${name}\n         ${String(error.message).split("\n")[0]}`);
  }
}

console.log(`Servidor: ${httpUrl}   WebSocket: ${wsUrl}   (ejecución ${runId})`);

// Las pruebas lentas (esperan tiempos reales del servidor) corren en paralelo con las rápidas.
const slow = [
  step("sin saludo, el servidor cierra la conexión a los ~10 s (4005)", async () => {
    const c = await connect();
    const info = await c.closed(25_000);
    assert.equal(info.code, 4005);
    const error = c.inbox.find((m) => m.t === "error");
    assert.equal(error?.code, "handshake_timeout");
  }),
  step("tras 13 s sin hablar (el servidor puede hibernar) todo sigue funcionando", async () => {
    const c = await connect();
    const welcome = await c.hello("hiberna");
    assert.equal(welcome.t, "welcome");
    await new Promise((done) => setTimeout(done, 13_000));
    c.send("ping");
    assert.equal(await c.next((m) => m === "pong"), "pong");
    c.send({ t: "stats" });
    const stats = await c.next((m) => m.t === "stats");
    assert.ok(stats.online >= 1);
    c.close();
    await c.closed();
    const again = await connect();
    const back = await again.hello("hiberna", { resume: welcome.session });
    assert.equal(back.resumed, true);
    assert.equal(back.session, welcome.session);
  }),
];

await step("GET /health responde ok", async () => {
  const response = await fetch(`${httpUrl}/health`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.protocol, PROTOCOL);
  assert.equal(typeof body.server, "string");
});

await step("saludo: llega welcome con código de sesión", async () => {
  const c = await connect();
  const welcome = await c.hello("ana");
  assert.equal(welcome.t, "welcome");
  assert.equal(welcome.v, PROTOCOL);
  assert.match(welcome.session, /^[a-f0-9]{32}$/);
  assert.equal(welcome.resumed, false);
  assert.equal(welcome.you.name, "ANA");
  assert.ok(welcome.online >= 1);
  c.close();
});

await step('el texto "ping" se contesta con "pong"', async () => {
  const c = await connect();
  await c.hello("ping");
  c.send("ping");
  assert.equal(await c.next((m) => m === "pong"), "pong");
  c.close();
});

await step("stats cuenta a los jugadores conectados", async () => {
  const a = await connect();
  const b = await connect();
  await a.hello("stats-a");
  await b.hello("stats-b");
  a.send({ t: "stats" });
  const stats = await a.next((m) => m.t === "stats");
  assert.ok(stats.online >= 2, `online=${stats.online}`);
  a.close();
  b.close();
});

await step("reanudar: tras cortar la conexión, el código recupera la sesión", async () => {
  const first = await connect();
  const welcome = await first.hello("resume");
  first.close();
  await first.closed();
  const second = await connect();
  const back = await second.hello("resume", { resume: welcome.session });
  assert.equal(back.t, "welcome");
  assert.equal(back.resumed, true);
  assert.equal(back.session, welcome.session);
  second.close();
});

await step("el mismo jugador desde otro lugar reemplaza a la conexión anterior (4000)", async () => {
  const first = await connect();
  const welcome = await first.hello("dup");
  const second = await connect();
  const back = await second.hello("dup", { resume: welcome.session });
  assert.equal(back.resumed, true);
  const bye = await first.next((m) => m.t === "bye");
  assert.equal(bye.reason, "replaced");
  assert.equal((await first.closed()).code, 4000);
  second.send({ t: "stats" });
  assert.equal((await second.next((m) => m.t === "stats")).t, "stats");
  second.close();
});

await step("versión de protocolo distinta: error bad_version y cierre 4001", async () => {
  const c = await connect();
  c.send({ t: "hello", v: 99, client: clientId("version"), name: "X" });
  const error = await c.next((m) => m.t === "error");
  assert.equal(error.code, "bad_version");
  assert.equal(error.supported, PROTOCOL);
  assert.equal((await c.closed()).code, 4001);
});

await step("mensaje que no es JSON antes del saludo: error y cierre 4002", async () => {
  const c = await connect();
  c.send("esto no es json");
  assert.equal((await c.next((m) => m.t === "error")).code, "bad_message");
  assert.equal((await c.closed()).code, 4002);
});

await step("pedir stats sin saludar: hello_required y cierre 4002", async () => {
  const c = await connect();
  c.send({ t: "stats" });
  assert.equal((await c.next((m) => m.t === "error")).code, "hello_required");
  assert.equal((await c.closed()).code, 4002);
});

await step("identificador de jugador inválido: bad_client y cierre 4002", async () => {
  const c = await connect();
  c.send({ t: "hello", v: PROTOCOL, client: "corto", name: "X" });
  assert.equal((await c.next((m) => m.t === "error")).code, "bad_client");
  assert.equal((await c.closed()).code, 4002);
});

await step("tres mensajes desconocidos seguidos cortan la conexión (4002)", async () => {
  const c = await connect();
  await c.hello("strikes");
  for (let i = 0; i < 3; i += 1) c.send({ t: "no-existe" });
  assert.equal((await c.next((m) => m.t === "error")).code, "unknown_type");
  assert.equal((await c.closed()).code, 4002);
});

await step("mensaje demasiado grande: too_big y cierre 4002", async () => {
  const c = await connect();
  await c.hello("grande");
  c.send(JSON.stringify({ t: "stats", relleno: "x".repeat(5000) }));
  assert.equal((await c.next((m) => m.t === "error")).code, "too_big");
  assert.equal((await c.closed()).code, 4002);
});

await step("demasiados mensajes seguidos: rate_limited y cierre 4003", async () => {
  const c = await connect();
  await c.hello("rapido");
  for (let i = 0; i < 120; i += 1) c.send({ t: "ping" });
  assert.equal((await c.next((m) => m.t === "error")).code, "rate_limited");
  assert.equal((await c.closed()).code, 4003);
});

await step("bye: la despedida cierra (1000) y descarta la sesión", async () => {
  const c = await connect();
  const welcome = await c.hello("bye");
  c.send({ t: "bye" });
  assert.equal((await c.closed()).code, 1000);
  const again = await connect();
  const back = await again.hello("bye", { resume: welcome.session });
  assert.equal(back.resumed, false);
  assert.notEqual(back.session, welcome.session);
  again.close();
});

await Promise.all(slow);

for (const client of open) client.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length} de ${results.length} comprobaciones correctas.`);
process.exit(failed.length === 0 ? 0 : 1);
