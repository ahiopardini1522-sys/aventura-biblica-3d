// Servidor WebSocket local para desarrollo: usa la MISMA lógica (hub_core.js) que el servidor de
// Cloudflare, pero sobre Node puro (sin npm ni cuenta de Cloudflare). Sirve para probar el juego
// y los scripts de e2e/ en una computadora sin desplegar nada.
//
//   node e2e/local_server.mjs [puerto]        (por defecto 8788)
//
// No es el servidor de producción: no guarda las sesiones en disco ni "hiberna".

import { createHash, randomUUID } from "node:crypto";
import http from "node:http";
import { fileURLToPath } from "node:url";

import { HubCore } from "../src/hub_core.js";
import { PROTOCOL_VERSION, SERVER_VERSION } from "../src/protocol.js";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function frame(opcode, payload) {
  const length = payload.length;
  let header;
  if (length < 126) {
    header = Buffer.from([0x80 | opcode, length]);
  } else if (length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }
  return Buffer.concat([header, payload]);
}

/** Lee los mensajes completos que hay en el búfer; devuelve lo que sobra. */
function parseFrames(buffer, onFrame) {
  let offset = 0;
  while (buffer.length - offset >= 2) {
    const first = buffer[offset];
    const second = buffer[offset + 1];
    let length = second & 0x7f;
    let position = offset + 2;
    if (length === 126) {
      if (buffer.length < position + 2) break;
      length = buffer.readUInt16BE(position);
      position += 2;
    } else if (length === 127) {
      if (buffer.length < position + 8) break;
      length = Number(buffer.readBigUInt64BE(position));
      position += 8;
    }
    const masked = (second & 0x80) !== 0;
    if (masked) position += 4;
    if (buffer.length < position + length) break;
    const payload = Buffer.from(buffer.subarray(position, position + length));
    if (masked) {
      const mask = buffer.subarray(position - 4, position);
      for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4];
    }
    onFrame({ fin: (first & 0x80) !== 0, opcode: first & 0x0f, payload });
    offset = position + length;
  }
  return buffer.subarray(offset);
}

export function startLocalServer(port = 8788, options = {}) {
  const core = new HubCore(options);
  const sockets = new Map();

  function apply(effects) {
    for (const { conn, text } of effects.out) {
      sockets.get(conn)?.write(frame(0x1, Buffer.from(text, "utf8")));
    }
    for (const { conn, code, reason } of effects.close) {
      const socket = sockets.get(conn);
      sockets.delete(conn);
      core.onClose(conn);
      if (!socket) continue;
      const body = Buffer.alloc(2 + Buffer.byteLength(reason ?? ""));
      body.writeUInt16BE(code, 0);
      body.write(reason ?? "", 2);
      socket.end(frame(0x8, body));
    }
  }

  const server = http.createServer((request, response) => {
    const path = new URL(request.url, "http://local").pathname;
    if (path === "/" || path === "/health") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ ok: true, service: "aventura-biblica-online", server: SERVER_VERSION, protocol: PROTOCOL_VERSION }));
    } else {
      response.writeHead(404, { "content-type": "application/json" });
      response.end(JSON.stringify({ ok: false }));
    }
  });

  server.on("upgrade", (request, socket) => {
    const key = request.headers["sec-websocket-key"];
    if (new URL(request.url, "http://local").pathname !== "/ws" || !key) {
      socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
      return;
    }
    const accept = createHash("sha1").update(key + GUID).digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);

    const id = randomUUID();
    sockets.set(id, socket);
    apply(core.onOpen(id, { ip: socket.remoteAddress ?? "" }));

    let pending = Buffer.alloc(0);
    let text = "";
    socket.on("data", (chunk) => {
      pending = parseFrames(Buffer.concat([pending, chunk]), ({ fin, opcode, payload }) => {
        if (opcode === 0x8) {
          sockets.delete(id);
          core.onClose(id);
          socket.end(frame(0x8, payload.subarray(0, 2)));
        } else if (opcode === 0x9) {
          socket.write(frame(0xa, payload));
        } else if (opcode === 0x1 || opcode === 0x0) {
          text += payload.toString("utf8");
          if (fin) {
            const message = text;
            text = "";
            apply(core.onMessage(id, message));
          }
        } else if (opcode === 0x2) {
          apply(core.onMessage(id, payload)); // binario: el núcleo lo rechaza
        }
      });
    });
    const gone = () => {
      if (sockets.get(id) === socket) sockets.delete(id);
      core.onClose(id);
    };
    socket.on("close", gone);
    socket.on("error", gone);
  });

  const timer = setInterval(() => apply(core.sweep()), 500);
  timer.unref();
  return new Promise((resolve) => {
    server.listen(port, "127.0.0.1", () => {
      resolve({
        port: server.address().port,
        core,
        close: () => new Promise((done) => {
          clearInterval(timer);
          for (const socket of sockets.values()) socket.destroy();
          server.close(() => done());
        }),
      });
    });
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.argv[2] ?? 8788);
  const { port: actual } = await startLocalServer(port);
  console.log(`Servidor local de prueba en http://127.0.0.1:${actual}  (WebSocket: ws://127.0.0.1:${actual}/ws)`);
}
