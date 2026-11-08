// Protocolo de la conexión en línea de Aventura Bíblica 3D (versión 1).
//
// Todo viaja como texto por una conexión WebSocket. Hay dos tipos de mensajes:
//   - El texto "ping": el servidor responde "pong" (latido barato; Cloudflare lo contesta sin
//     despertar al servidor, así que no cuesta nada mantener la conexión abierta).
//   - Un objeto JSON con el campo "t" (tipo). Ejemplos:
//       cliente -> servidor  {"t":"hello","v":1,"client":"<id>","name":"Ana","app":"0.4.0","resume":"<sesión>"}
//       servidor -> cliente  {"t":"welcome","v":1,"session":"<sesión>","resumed":false,"server":"0.1.0",...}
//
// Este archivo no depende de Cloudflare: lo usan el servidor, las pruebas de Node y, como
// referencia, el cliente de Godot (scripts/online/online_protocol.gd repite estas constantes).

export const PROTOCOL_VERSION = 1;
export const SERVER_VERSION = "0.1.0";

// Códigos con los que el servidor cierra una conexión (los de 4000 a 4999 son de la aplicación).
export const CLOSE = Object.freeze({
  REPLACED: 4000, // el mismo jugador se conectó desde otro lugar
  BAD_VERSION: 4001, // la versión del protocolo no coincide
  BAD_MESSAGE: 4002, // mensaje mal formado o demasiado grande
  RATE_LIMITED: 4003, // demasiados mensajes seguidos
  TOO_MANY: 4004, // el servidor o esa dirección tienen demasiadas conexiones
  HANDSHAKE_TIMEOUT: 4005, // no llegó el "hello" a tiempo
});

// Límites (protegen la cuota gratuita del servidor y a los demás jugadores).
export const LIMITS = Object.freeze({
  MAX_MESSAGE_CHARS: 4096,
  RATE_CAPACITY: 40, // mensajes que se pueden mandar de golpe
  RATE_REFILL_PER_SECOND: 10, // y cuántos se recuperan por segundo
  MAX_CONNECTIONS: 300,
  MAX_SESSIONS: 600, // sesiones guardadas (conectadas + las que esperan una reconexión)
  MAX_PER_IP: 20, // varios jugadores pueden compartir la misma dirección (wifi de casa, red móvil)
  HANDSHAKE_TIMEOUT_MS: 10_000,
  SESSION_TTL_MS: 15 * 60 * 1000, // cuánto se guarda una sesión desde que se corta la conexión
  MAX_STRIKES: 3, // mensajes inválidos tolerados después del saludo
  NAME_MAX_CHARS: 20,
});

const CLIENT_ID_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;
const SESSION_PATTERN = /^[a-f0-9]{32}$/;

export function encode(message) {
  return JSON.stringify(message);
}

/** Convierte un texto en objeto; devuelve null si no es un objeto JSON con "t" de texto. */
export function decode(text) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  if (typeof value.t !== "string" || value.t.length === 0 || value.t.length > 32) return null;
  return value;
}

/** Quita caracteres de control y espacios sobrantes; recorta al largo máximo. */
export function cleanName(raw) {
  if (typeof raw !== "string") return "";
  // eslint-disable-next-line no-control-regex
  const withoutControls = raw.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202f\u2060-\u206f\ufeff]/g, "");
  const trimmed = withoutControls.replace(/\s+/g, " ").trim();
  return Array.from(trimmed).slice(0, LIMITS.NAME_MAX_CHARS).join("");
}

export function isValidClientId(value) {
  return typeof value === "string" && CLIENT_ID_PATTERN.test(value);
}

export function isValidSession(value) {
  return typeof value === "string" && SESSION_PATTERN.test(value);
}
