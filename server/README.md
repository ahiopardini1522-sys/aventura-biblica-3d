# Servidor en línea de Aventura Bíblica 3D

Servidor de **Cloudflare Workers** con un **Durable Object** (`Hub`) que mantiene las conexiones WebSocket del juego.
Fase 4.1: saludo, latido, estadísticas y reanudación de sesión. Las salas, el emparejamiento y los turnos (fases 4.2 y
4.3) se agregarán sobre esta base.

* Diseño y decisiones: [`docs/online/ARQUITECTURA.md`](../docs/online/ARQUITECTURA.md)
* Publicarlo desde el teléfono (cuenta de Cloudflare, secretos de GitHub, botón): [`docs/online/CONFIGURAR_SERVIDOR.md`](../docs/online/CONFIGURAR_SERVIDOR.md)

## Carpetas

| Ruta | Qué hay |
| --- | --- |
| `src/worker.js` | Pegamento con Cloudflare: el Worker (`/`, `/health`, `/ws`) y el Durable Object `Hub` (API de hibernación de WebSocket, alarmas, restauración de conexiones tras dormir). |
| `src/hub_core.js` | Lógica pura (sin nada de Cloudflare): conexiones, saludo, sesiones, límites y estadísticas. Devuelve "efectos" (mensajes a enviar y conexiones a cerrar). |
| `src/protocol.js` | Protocolo versión 1: tipos de mensaje, códigos de cierre, límites y validación. Lo comparte con `scripts/online/online_protocol.gd` del juego (las pruebas del juego comprueban que coinciden). |
| `test/` | Pruebas de Node con `node --test` (reloj falso y Cloudflare simulado en `test/support/`). |
| `e2e/e2e.mjs` | Pruebas de extremo a extremo contra un servidor real por WebSocket. |
| `e2e/local_server.mjs` | Servidor local de Node con la misma lógica (`hub_core.js`) para probar sin Cloudflare. No es el de producción. |
| `e2e/probe_close.mjs` | Sondeo de diagnóstico sobre cómo se cierra una conexión que nunca saluda (no es una prueba). |
| `wrangler.toml` | Configuración de Cloudflare: nombre `aventura-biblica-online`, Durable Object `HUB`, migración SQLite `v1`. |

## Comandos

Hace falta Node 22 o más nuevo.

```
cd server
npm install              # solo para wrangler (dev y deploy); las pruebas no lo necesitan
npm test                 # 52 pruebas de Node, sin red ni cuenta de Cloudflare
npm run dev              # wrangler dev: el mismo motor (workerd) que Cloudflare, en http://127.0.0.1:8787
node e2e/e2e.mjs http://127.0.0.1:8787     # 17 comprobaciones contra un servidor en marcha
node e2e/local_server.mjs 8788             # servidor local de Node, sin wrangler
npm run deploy           # publica (necesita CLOUDFLARE_API_TOKEN y CLOUDFLARE_ACCOUNT_ID); normalmente lo hace GitHub
```

No hace falta nada de esto para usar el juego: GitHub Actions ejecuta las pruebas en cada subida
(`.github/workflows/build.yml`, trabajo `en_linea`) y publica el servidor con
`.github/workflows/servidor-desplegar.yml`.

## Direcciones

| Ruta | Respuesta |
| --- | --- |
| `GET /` y `GET /health` | JSON `{"ok":true,"service":"aventura-biblica-online","server":…,"protocol":1}` |
| `GET /ws` con `Upgrade: websocket` | Conexión del juego (solo `wss://` en producción) |
| `GET /ws` sin `Upgrade` | `426 Upgrade Required` |

## Reglas que no se rompen

* **Sin secretos en el código ni en el APK.** Las claves de Cloudflare solo son secretos de GitHub.
* **Nada de datos personales:** el servidor no guarda cuentas, correos ni contraseñas; solo un identificador anónimo al
  azar por dispositivo y un nombre público de hasta 20 caracteres.
* **Toda entrada del cliente es sospechosa:** tamaño máximo de mensaje, ritmo limitado, formato validado, tres avisos
  y se corta. Los límites están en `src/protocol.js` y se explican en `ARQUITECTURA.md`.
* La carpeta `server/` **no** entra en el APK (`export_presets.cfg` la excluye).
