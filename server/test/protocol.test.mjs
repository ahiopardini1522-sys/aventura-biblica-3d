// Pruebas de las funciones de apoyo del protocolo.

import assert from "node:assert/strict";
import { test } from "node:test";

import { PROTOCOL_VERSION, cleanName, decode, encode, isValidClientId, isValidSession } from "../src/protocol.js";

test("encode y decode son inversos para objetos con tipo", () => {
  const message = { t: "hello", v: PROTOCOL_VERSION, name: "Ana" };
  assert.deepEqual(decode(encode(message)), message);
});

test("decode rechaza lo que no es un objeto JSON con tipo de texto", () => {
  for (const texto of ["", "x", "{", "[]", "[{\"t\":\"a\"}]", "null", "true", "7", "\"hola\"", "{\"t\":1}", "{\"t\":\"\"}", "{}"]) {
    assert.equal(decode(texto), null, texto);
  }
  assert.equal(decode(JSON.stringify({ t: "x".repeat(33) })), null);
  assert.notEqual(decode(JSON.stringify({ t: "x".repeat(32) })), null);
});

test("cleanName quita controles, invisibles y espacios repetidos", () => {
  assert.equal(cleanName("  Ana   María "), "Ana María");
  assert.equal(cleanName("A\u0000b\u0007c"), "Abc");
  assert.equal(cleanName("Zero​Width"), "ZeroWidth");
  assert.equal(cleanName("‮atrás"), "atrás");
  assert.equal(cleanName(null), "");
  assert.equal(cleanName(42), "");
  assert.equal(Array.from(cleanName("ñ".repeat(100))).length, 20);
});

test("validación de identificadores", () => {
  assert.equal(isValidClientId("abcdefghijklmnop"), true);
  assert.equal(isValidClientId("abcdefghijklmno"), false, "muy corto");
  assert.equal(isValidClientId("a".repeat(65)), false, "muy largo");
  assert.equal(isValidClientId("tiene espacios aqui!"), false);
  assert.equal(isValidClientId(12345678901234567890), false);
  assert.equal(isValidSession("0123456789abcdef0123456789abcdef"), true);
  assert.equal(isValidSession("0123456789ABCDEF0123456789abcdef"), false, "solo minúsculas");
  assert.equal(isValidSession("0123"), false);
  assert.equal(isValidSession(null), false);
});
