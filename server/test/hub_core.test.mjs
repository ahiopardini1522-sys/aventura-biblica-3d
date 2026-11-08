// Pruebas de la lógica del servidor en línea. Se ejecutan con: node --test (en la carpeta server/).
// No necesitan red ni Cloudflare: usan un reloj falso para controlar el tiempo.

import assert from "node:assert/strict";
import { test } from "node:test";

import { HubCore } from "../src/hub_core.js";
import { CLOSE, LIMITS, PROTOCOL_VERSION } from "../src/protocol.js";

const CLIENT_A = "cliente-aaaaaaaaaaaaaaaa";
const CLIENT_B = "cliente-bbbbbbbbbbbbbbbb";
const CLIENT_C = "cliente-cccccccccccccccc";

function makeHub(limits = {}) {
  const clock = { now: 1_000_000 };
  let counter = 0;
  const hub = new HubCore({
    now: () => clock.now,
    randomHex: (bytes) => (++counter).toString(16).padStart(bytes * 2, "0"),
    limits,
  });
  return { hub, clock };
}

const messages = (effects) => effects.out.map((o) => (o.text === "pong" ? "pong" : JSON.parse(o.text)));
const only = (effects) => {
  const list = messages(effects);
  assert.equal(list.length, 1, `se esperaba 1 mensaje y hubo ${list.length}: ${JSON.stringify(list)}`);
  return list[0];
};
const hello = (extra = {}) => JSON.stringify({ t: "hello", v: PROTOCOL_VERSION, client: CLIENT_A, name: "Ana", ...extra });

function join(hub, connId, extra = {}, ip = "") {
  hub.onOpen(connId, { ip });
  const effects = hub.onMessage(connId, hello(extra));
  return only(effects);
}

test("el saludo correcto devuelve welcome con un código de sesión", () => {
  const { hub } = makeHub();
  hub.onOpen("c1");
  const welcome = only(hub.onMessage("c1", hello()));
  assert.equal(welcome.t, "welcome");
  assert.equal(welcome.v, PROTOCOL_VERSION);
  assert.match(welcome.session, /^[a-f0-9]{32}$/);
  assert.equal(welcome.resumed, false);
  assert.equal(welcome.online, 1);
  assert.deepEqual(welcome.you, { client: CLIENT_A, name: "Ana" });
  assert.equal(hub.onlineCount(), 1);
  assert.equal(hub.dirty, true);
});

test("un saludo sin versión, con otra versión o con un identificador inválido se rechaza", () => {
  const { hub } = makeHub();

  hub.onOpen("sin-version");
  let effects = hub.onMessage("sin-version", JSON.stringify({ t: "hello", client: CLIENT_A }));
  assert.equal(only(effects).code, "bad_message");
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);

  hub.onOpen("otra-version");
  effects = hub.onMessage("otra-version", hello({ v: 99 }));
  const error = only(effects);
  assert.equal(error.code, "bad_version");
  assert.equal(error.supported, PROTOCOL_VERSION);
  assert.equal(effects.close[0].code, CLOSE.BAD_VERSION);

  hub.onOpen("mal-id");
  effects = hub.onMessage("mal-id", hello({ client: "corto" }));
  assert.equal(only(effects).code, "bad_client");
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);

  assert.equal(hub.onlineCount(), 0);
  assert.equal(hub.conns.size, 0, "las conexiones rechazadas se dan de baja");
});

test("el nombre se limpia: sin caracteres de control, sin espacios de más y con largo máximo", () => {
  const { hub } = makeHub();
  const nombres = [
    ["  Ana\u0000 \n  María  ", "Ana María"],
    ["", "Jugador"],
    ["​‌", "Jugador"],
    ["x".repeat(50), "x".repeat(LIMITS.NAME_MAX_CHARS)],
    ["😀".repeat(30), "😀".repeat(LIMITS.NAME_MAX_CHARS)],
  ];
  nombres.forEach(([entrada, esperado], i) => {
    const welcome = join(hub, `n${i}`, { client: `cliente-nombre-${String(i).padStart(8, "0")}`, name: entrada });
    assert.equal(welcome.you.name, esperado);
  });
  const sinNombre = join(hub, "sin-nombre", { client: "cliente-sin-nombre-0000", name: undefined });
  assert.equal(sinNombre.you.name, "Jugador");
});

test("antes del saludo solo se aceptan ping y hello", () => {
  const { hub } = makeHub();
  hub.onOpen("c1");
  assert.equal(only(hub.onMessage("c1", "ping")), "pong");
  assert.equal(only(hub.onMessage("c1", JSON.stringify({ t: "ping" }))).t, "pong");

  const effects = hub.onMessage("c1", JSON.stringify({ t: "stats" }));
  assert.equal(only(effects).code, "hello_required");
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);
});

test("un mensaje que no es JSON válido o no trae tipo se rechaza", () => {
  const { hub } = makeHub();
  for (const texto of ["hola", "{", "[]", "null", "42", JSON.stringify({ x: 1 }), JSON.stringify({ t: "" }), JSON.stringify({ t: "x".repeat(40) })]) {
    const { hub: h } = makeHub();
    h.onOpen("c1");
    const effects = h.onMessage("c1", texto);
    assert.equal(only(effects).code, "bad_message", texto);
    assert.equal(effects.close.length, 1, texto);
  }
  assert.equal(hub.conns.size, 0);
});

test("después del saludo, stats cuenta a los jugadores conectados", () => {
  const { hub } = makeHub();
  join(hub, "c1");
  join(hub, "c2", { client: CLIENT_B, name: "Beto" });
  assert.deepEqual(only(hub.onMessage("c1", JSON.stringify({ t: "stats" }))), { t: "stats", online: 2 });
  hub.onClose("c2");
  assert.deepEqual(only(hub.onMessage("c1", JSON.stringify({ t: "stats" }))), { t: "stats", online: 1 });
});

test("las conexiones sin saludo no cuentan como jugadores", () => {
  const { hub } = makeHub();
  hub.onOpen("c1");
  hub.onOpen("c2");
  assert.equal(hub.onlineCount(), 0);
  join(hub, "c3", { client: CLIENT_C });
  assert.equal(hub.onlineCount(), 1);
});

test("saludar dos veces cuenta como mensaje inválido", () => {
  const { hub } = makeHub();
  join(hub, "c1");
  const effects = hub.onMessage("c1", hello());
  assert.equal(only(effects).code, "already_hello");
  assert.equal(effects.close.length, 0, "el primer error se tolera");
});

test("tres mensajes inválidos seguidos después del saludo cortan la conexión", () => {
  const { hub } = makeHub();
  join(hub, "c1");
  const desconocido = JSON.stringify({ t: "no-existe" });
  assert.equal(only(hub.onMessage("c1", desconocido)).code, "unknown_type");
  assert.equal(only(hub.onMessage("c1", "basura")).code, "bad_message");
  const effects = hub.onMessage("c1", desconocido);
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);
  assert.equal(hub.onlineCount(), 0);
});

test("reanudar: con el código de sesión el jugador recupera su sesión", () => {
  const { hub, clock } = makeHub();
  const first = join(hub, "c1");
  hub.onClose("c1");
  clock.now += 60_000;
  const second = join(hub, "c2", { resume: first.session });
  assert.equal(second.resumed, true);
  assert.equal(second.session, first.session);
  assert.equal(hub.sessions.get(first.session).expires, null, "la sesión vuelve a estar activa");
  assert.equal(hub.onlineCount(), 1);
});

test("reanudar con la conexión anterior todavía abierta reemplaza a la anterior", () => {
  const { hub } = makeHub();
  const first = join(hub, "c1");
  hub.onOpen("c2");
  const effects = hub.onMessage("c2", hello({ resume: first.session }));
  const list = messages(effects);
  assert.deepEqual(list[0], { t: "bye", reason: "replaced" });
  assert.equal(effects.out[0].conn, "c1");
  assert.deepEqual(effects.close, [{ conn: "c1", code: CLOSE.REPLACED, reason: "replaced" }]);
  assert.equal(list[1].t, "welcome");
  assert.equal(list[1].resumed, true);
  assert.equal(list[1].online, 1, "sigue siendo un solo jugador");
  assert.equal(hub.onlineCount(), 1);
  assert.deepEqual(hub.onClose("c1"), { out: [], close: [] }, "el cierre tardío de la conexión vieja no afecta");
  assert.equal(hub.onlineCount(), 1);
  assert.equal(hub.sessions.get(first.session).expires, null);
});

test("saludar con el mismo jugador sin código reemplaza la conexión y crea otra sesión", () => {
  const { hub } = makeHub();
  const first = join(hub, "c1");
  hub.onOpen("c2");
  const list = messages(hub.onMessage("c2", hello()));
  assert.equal(list[1].resumed, false);
  assert.notEqual(list[1].session, first.session);
  assert.equal(hub.sessions.has(first.session), false, "la sesión vieja se borra");
  assert.equal(hub.sessions.size, 1);
});

test("la sesión vence a los 15 minutos de cortarse la conexión", () => {
  const { hub, clock } = makeHub();
  const first = join(hub, "c1");
  hub.onClose("c1");
  clock.now += LIMITS.SESSION_TTL_MS - 1;
  assert.equal(join(hub, "c2", { resume: first.session }).resumed, true);
  hub.onClose("c2");
  clock.now += LIMITS.SESSION_TTL_MS;
  const late = join(hub, "c3", { resume: first.session });
  assert.equal(late.resumed, false);
  assert.notEqual(late.session, first.session);
});

test("un código de sesión de otro jugador, inventado o mal formado no se reanuda", () => {
  const { hub } = makeHub();
  const ana = join(hub, "c1");
  const beto = join(hub, "c2", { client: CLIENT_B, name: "Beto" });
  assert.equal(join(hub, "c3", { client: CLIENT_C, resume: ana.session }).resumed, false);
  assert.equal(join(hub, "c4", { client: "cliente-dddddddddddddddd", resume: "f".repeat(32) }).resumed, false);
  assert.equal(join(hub, "c5", { client: "cliente-eeeeeeeeeeeeeeee", resume: "no-valido" }).resumed, false);
  assert.ok(hub.sessions.has(ana.session), "la sesión de Ana sigue intacta");
  assert.ok(hub.sessions.has(beto.session));
});

test("bye: la despedida cierra la conexión y borra la sesión", () => {
  const { hub } = makeHub();
  const welcome = join(hub, "c1");
  const effects = hub.onMessage("c1", JSON.stringify({ t: "bye" }));
  assert.deepEqual(effects.close, [{ conn: "c1", code: 1000, reason: "bye" }]);
  assert.equal(hub.sessions.has(welcome.session), false);
  assert.equal(hub.onlineCount(), 0);
  assert.equal(join(hub, "c2", { resume: welcome.session }).resumed, false);
});

test("limitador de velocidad: demasiados mensajes seguidos cortan la conexión", () => {
  const { hub } = makeHub();
  join(hub, "c1");
  const ping = JSON.stringify({ t: "ping" });
  // El saludo ya gastó 1 de los 40 cupos.
  for (let i = 0; i < LIMITS.RATE_CAPACITY - 1; i += 1) {
    assert.equal(only(hub.onMessage("c1", ping)).t, "pong");
  }
  const effects = hub.onMessage("c1", ping);
  assert.equal(only(effects).code, "rate_limited");
  assert.equal(effects.close[0].code, CLOSE.RATE_LIMITED);
  assert.equal(hub.onlineCount(), 0);

  // Con el paso del tiempo los cupos se recuperan.
  const { hub: otro, clock: reloj } = makeHub();
  join(otro, "c1");
  for (let i = 0; i < LIMITS.RATE_CAPACITY - 1; i += 1) otro.onMessage("c1", ping);
  reloj.now += 1000; // +10 cupos
  for (let i = 0; i < 10; i += 1) assert.equal(only(otro.onMessage("c1", ping)).t, "pong");
});

test("un mensaje demasiado grande o binario se rechaza", () => {
  const { hub } = makeHub();
  join(hub, "c1");
  let effects = hub.onMessage("c1", "x".repeat(LIMITS.MAX_MESSAGE_CHARS + 1));
  assert.equal(only(effects).code, "too_big");
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);

  join(hub, "c2", { client: CLIENT_B });
  effects = hub.onMessage("c2", new ArrayBuffer(8));
  assert.equal(only(effects).code, "bad_message");
  assert.equal(effects.close[0].code, CLOSE.BAD_MESSAGE);
});

test("el servidor limita las conexiones totales y por dirección", () => {
  const { hub } = makeHub({ MAX_CONNECTIONS: 5, MAX_PER_IP: 2 });
  hub.onOpen("a1", { ip: "1.1.1.1" });
  hub.onOpen("a2", { ip: "1.1.1.1" });
  const tercera = hub.onOpen("a3", { ip: "1.1.1.1" });
  assert.equal(only(tercera).code, "too_many_connections");
  assert.equal(tercera.close[0].code, CLOSE.TOO_MANY);
  assert.equal(hub.conns.size, 2, "la rechazada no queda registrada");

  hub.onOpen("b1", { ip: "2.2.2.2" });
  hub.onOpen("b2", { ip: "2.2.2.2" });
  hub.onOpen("c1", { ip: "3.3.3.3" });
  const llena = hub.onOpen("d1", { ip: "4.4.4.4" });
  assert.equal(llena.close[0].code, CLOSE.TOO_MANY);
  hub.onClose("a1");
  assert.equal(hub.onOpen("d2", { ip: "4.4.4.4" }).close.length, 0, "al liberarse un lugar se vuelve a aceptar");
});

test("sin dirección conocida no se aplica el límite por dirección", () => {
  const { hub } = makeHub({ MAX_PER_IP: 1 });
  for (let i = 0; i < 5; i += 1) assert.equal(hub.onOpen(`c${i}`).close.length, 0);
});

test("si no llega el saludo a tiempo, sweep cierra la conexión", () => {
  const { hub, clock } = makeHub();
  hub.onOpen("tarde");
  join(hub, "listo", { client: CLIENT_B });
  assert.equal(hub.nextWake(), clock.now + LIMITS.HANDSHAKE_TIMEOUT_MS);

  clock.now += LIMITS.HANDSHAKE_TIMEOUT_MS - 1;
  assert.equal(hub.sweep().close.length, 0);

  clock.now += 1;
  const effects = hub.sweep();
  assert.equal(only(effects).code, "handshake_timeout");
  assert.deepEqual(effects.close, [{ conn: "tarde", code: CLOSE.HANDSHAKE_TIMEOUT, reason: "handshake_timeout" }]);
  assert.equal(hub.conns.has("tarde"), false);
  assert.equal(hub.conns.has("listo"), true, "el que saludó no se toca");
  assert.equal(hub.nextWake(), null, "ya no hay nada que vigilar");
});

test("sweep borra las sesiones vencidas y nextWake avisa cuándo volver", () => {
  const { hub, clock } = makeHub();
  const first = join(hub, "c1");
  assert.equal(hub.nextWake(), null, "una sesión conectada no vence");
  hub.onClose("c1");
  assert.equal(hub.nextWake(), clock.now + LIMITS.SESSION_TTL_MS);

  clock.now += LIMITS.SESSION_TTL_MS;
  hub.dirty = false;
  hub.sweep();
  assert.equal(hub.sessions.has(first.session), false);
  assert.equal(hub.sessionByClient.size, 0);
  assert.equal(hub.dirty, true, "hay que guardar el cambio");
  assert.equal(hub.nextWake(), null);
});

test("sesiones guardadas: se limita su cantidad y se descartan primero las que antes vencen", () => {
  const { hub, clock } = makeHub({ MAX_SESSIONS: 3 });
  const tokens = [];
  for (let i = 0; i < 3; i += 1) {
    tokens.push(join(hub, `c${i}`, { client: `cliente-lote-${String(i).padStart(10, "0")}` }).session);
    hub.onClose(`c${i}`);
    clock.now += 1000;
  }
  assert.equal(hub.sessions.size, 3);
  const nueva = join(hub, "nueva", { client: "cliente-lote-nueva-0000" });
  assert.equal(hub.sessions.size, 3);
  assert.equal(hub.sessions.has(tokens[0]), false, "se descartó la más antigua");
  assert.equal(hub.sessions.has(tokens[1]), true);
  assert.equal(hub.sessions.has(nueva.session), true);
});

test("estado guardado: las sesiones sobreviven a un reinicio del servidor", () => {
  const { hub, clock } = makeHub();
  const ana = join(hub, "c1");
  join(hub, "c2", { client: CLIENT_B, name: "Beto" });
  hub.onClose("c2");

  const saved = JSON.parse(JSON.stringify(hub.exportState()));
  const conn = JSON.parse(JSON.stringify(hub.exportConn("c1")));

  // Un servidor nuevo (el anterior se durmió) con el mismo reloj.
  const { hub: despierto } = makeHub();
  despierto.now = () => clock.now;
  despierto.importState(saved);
  assert.equal(despierto.dirty, false);
  assert.equal(despierto.restoreConn(conn), true);
  assert.equal(despierto.restoreConn(conn), false, "restaurar dos veces no duplica");
  assert.equal(despierto.onlineCount(), 1);
  assert.equal(only(despierto.onMessage("c1", JSON.stringify({ t: "stats" }))).online, 1);

  // Ana sigue conectada: si se corta, su sesión empieza a vencer.
  despierto.onClose("c1");
  assert.equal(despierto.sessions.get(ana.session).expires, clock.now + LIMITS.SESSION_TTL_MS);

  // Y Beto, que se había ido antes de dormirse, puede reanudar.
  const betoSession = [...despierto.sessions].find(([, s]) => s.clientId === CLIENT_B)[0];
  despierto.onOpen("c9");
  const welcome = only(despierto.onMessage("c9", hello({ client: CLIENT_B, resume: betoSession })));
  assert.equal(welcome.resumed, true);
});

test("estado guardado dañado o con datos raros se ignora sin romper nada", () => {
  const { hub } = makeHub();
  for (const estado of [undefined, null, 42, "x", {}, { sessions: "no" }, { sessions: [null, 3, ["malo"], ["f".repeat(32), null]] }]) {
    hub.importState(estado);
    assert.equal(hub.sessions.size, 0);
  }
  hub.importState({ sessions: [["a".repeat(32), { clientId: CLIENT_A, name: "Ana", expires: "ayer" }]] });
  assert.equal(hub.sessions.get("a".repeat(32)).expires, null);
  assert.equal(hub.restoreConn(null), false);
  assert.equal(hub.restoreConn({ id: "" }), false);
  assert.equal(hub.restoreConn({ id: "z", helloDone: true, clientId: "malo" }), true);
  assert.equal(hub.onlineCount(), 0, "sin identificador válido no cuenta como jugador");
});

test("una sesión huérfana tras un reinicio empieza a vencer en el primer sweep", () => {
  const { hub, clock } = makeHub();
  hub.importState({ sessions: [["b".repeat(32), { clientId: CLIENT_A, name: "Ana", expires: null }]] });
  assert.equal(hub.nextWake(), clock.now, "hay que revisar ya");
  hub.sweep();
  assert.equal(hub.sessions.get("b".repeat(32)).expires, clock.now + LIMITS.SESSION_TTL_MS);
  assert.equal(hub.dirty, true);
});

test("cerrar una conexión desconocida no hace nada", () => {
  const { hub } = makeHub();
  assert.deepEqual(hub.onClose("nadie"), { out: [], close: [] });
  assert.deepEqual(hub.onMessage("nadie", "ping"), { out: [], close: [] });
});

test("restaurar una conexión vieja no le quita el lugar a la conexión activa del mismo jugador", () => {
  const { hub } = makeHub();
  const first = join(hub, "c1");
  const viejo = JSON.parse(JSON.stringify(hub.exportConn("c1")));
  hub.onOpen("c2");
  hub.onMessage("c2", hello({ resume: first.session }));
  assert.equal(hub.active.get(CLIENT_A), "c2");
  assert.equal(hub.restoreConn(viejo), true);
  assert.equal(hub.active.get(CLIENT_A), "c2", "la conexión activa no cambia");
  hub.onClose("c1");
  assert.equal(hub.sessions.get(first.session).expires, null, "cerrar la vieja no manda a vencer la sesión activa");
  assert.equal(hub.onlineCount(), 1, "queda solo la conexión nueva");
});
