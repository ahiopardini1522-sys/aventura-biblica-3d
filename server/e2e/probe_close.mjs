// Sondeo de diagnóstico (no es una prueba): mira, con marcas de tiempo, cómo se cierra una conexión
// cuando el servidor la corta por no saludar a tiempo, según lo que haya hecho el cliente antes.
//
//   node e2e/probe_close.mjs http://127.0.0.1:8787
//
// A: no envía nada.            B: envía "ping" y espera.           C: al recibir el error, cierra él mismo.

const rawUrl = process.argv[2] ?? process.env.SERVER_URL;
if (!rawUrl) {
  console.error("Falta la dirección del servidor.");
  process.exit(2);
}
const wsUrl = `${rawUrl.replace(/^ws/, "http").replace(/\/+$/, "").replace(/\/ws$/, "").replace(/^http/, "ws")}/ws`;

function probe(name, onOpen, onMessage, waitMs = 22_000) {
  return new Promise((resolve) => {
    const started = Date.now();
    const at = () => `${((Date.now() - started) / 1000).toFixed(2)} s`;
    const log = (text) => console.log(`[${name}] ${at()}  ${text}`);
    const socket = new WebSocket(wsUrl);
    let closed = false;
    const finish = (why) => {
      log(`${why}; estado final ${socket.readyState}`);
      resolve();
    };
    socket.addEventListener("open", () => {
      log("abierta");
      onOpen?.(socket, log);
    });
    socket.addEventListener("message", (event) => {
      log(`mensaje: ${String(event.data).slice(0, 80)}`);
      onMessage?.(socket, String(event.data), log);
    });
    socket.addEventListener("error", () => log("evento error"));
    socket.addEventListener("close", (event) => {
      closed = true;
      log(`CERRADA código=${event.code} razón=${event.reason} limpia=${event.wasClean}`);
      finish("terminó");
    });
    setTimeout(() => {
      if (!closed) finish("SIN CIERRE tras la espera");
    }, waitMs);
  });
}

await Promise.all([
  probe("A sin enviar nada"),
  probe("B ping primero", (socket) => socket.send("ping")),
  probe("C cierra el cliente", null, (socket, text, log) => {
    if (text.includes("handshake_timeout")) {
      log("el cliente cierra por su cuenta");
      socket.close(1000, "listo");
    }
  }),
]);
process.exit(0);
