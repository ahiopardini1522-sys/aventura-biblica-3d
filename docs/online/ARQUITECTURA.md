# Arquitectura del juego en línea (Etapa 4.1)

Esta es la base técnica del multijugador en línea. En esta fase **solo existe la conexión**: el juego abre
una conexión segura con un servidor propio, se identifica, mantiene el contacto y se recupera si se corta la
señal. Las partidas con amigos, los oponentes al azar y los turnos sincronizados se construyen encima en las
fases siguientes (4.2 y 4.3).

## Piezas

```
 Teléfono (Godot)                                        Internet                  Cloudflare (plan gratuito)
┌──────────────────────────────┐                                              ┌────────────────────────────────┐
│ OnlineManager   (autoload)   │                                              │ Worker  (server/src/worker.js) │
│  └─ OnlineClient (reintentos,│   wss://<servidor>.workers.dev/ws            │  /health  → estado en JSON     │
│     latido, sesión)          │ ───────────────────────────────────────────▶ │  /ws      → WebSocket          │
│      └─ WebSocketTransport   │ ◀─────────────────────────────────────────── │       │                        │
│          (WebSocketPeer)     │        mensajes de texto (JSON)              │       ▼                        │
└──────────────────────────────┘                                              │ Durable Object "Hub"           │
                                                                              │  └─ HubCore (lógica pura)      │
                                                                              └────────────────────────────────┘
```

| Pieza | Dónde | Qué hace |
| --- | --- | --- |
| `OnlineManager` | `scripts/online/online_manager.gd` (autoload) | Es lo único que ve el resto del juego: dice si el servidor está configurado, abre y cierra la conexión, y avisa con una señal cuando cambia el estado. Solo mantiene la conexión mientras la pantalla **MULTIJUGADOR** está abierta. |
| `OnlineClient` | `scripts/online/online_client.gd` | Máquina de estados de la conexión (`IDLE`, `CONNECTING`, `HANDSHAKE`, `ONLINE`, `WAITING`, `FAILED`). Se mueve con `tick(delta)`, sin hilos ni señales internas, para poder probarla de forma determinista. |
| `OnlineTransport` / `WebSocketTransport` | `scripts/online/` | El transporte es intercambiable: el real usa `WebSocketPeer` de Godot; las pruebas usan uno falso (`tools/fake_online_transport.gd`). |
| `OnlineProtocol` / `OnlineConfig` | `scripts/online/` | Mensajes y constantes del protocolo (idénticos a `server/src/protocol.js`; una prueba lo comprueba) y lectura de `data/online.json` y del identificador del dispositivo. |
| Worker | `server/src/worker.js` | Recibe las peticiones. `/health` responde `{ok:true,...}`; `/ws` entrega la conexión al Durable Object. |
| `Hub` (Durable Object) | `server/src/worker.js` | Mantiene las conexiones WebSocket con la **API de hibernación** (el servidor puede "dormir" sin cortar a nadie) y guarda las sesiones en su almacenamiento. |
| `HubCore` | `server/src/hub_core.js` | Toda la lógica del servidor, **sin depender de Cloudflare**: saludo, sesiones, límites, reemplazo de dispositivo, tiempos de espera. Se prueba en Node con relojes y conexiones falsas. |

## Identidad anónima y sesiones

* No hay cuentas ni contraseñas. Cada dispositivo crea una vez un **identificador aleatorio** (24 caracteres
  hexadecimales, `user://online.cfg`). No contiene datos personales.
* El servidor, al recibir el saludo, entrega un **código de sesión** (32 caracteres hexadecimales). Si la
  conexión se corta, el juego lo presenta al reconectar y el servidor reconoce al jugador (`resumed: true`).
  La sesión se conserva **15 minutos** desde el corte.
* Si el mismo jugador se conecta desde otro dispositivo, el servidor avisa al anterior (`bye` con motivo
  `replaced`), lo cierra con el código 4000 y el anterior **no reintenta** (así dos teléfonos no se pelean).
* El nombre se limpia en el servidor (caracteres de control, invisibles y de dirección de texto fuera; máximo
  20 caracteres).

## Mensajes (protocolo versión 1)

Todo viaja como **texto**. Dos clases:

* El texto `ping` → el servidor contesta `pong`. Cloudflare lo contesta por su cuenta sin despertar al
  servidor, así que el latido casi no cuesta nada.
* Objetos JSON con un campo `t` (tipo):

| Dirección | Tipo | Contenido |
| --- | --- | --- |
| juego → servidor | `hello` | `v` (versión del protocolo), `client` (identificador), `name`, `app` (versión del juego) y, opcional, `resume` (código de sesión). Tiene que ser lo primero. |
| servidor → juego | `welcome` | `v`, `session`, `resumed`, `server`, `now`, `online` (jugadores conectados) y `you`. |
| juego → servidor | `stats` | Pide el número de jugadores conectados. |
| servidor → juego | `stats` | `online`. |
| juego → servidor | `bye` | Despedida voluntaria: el servidor descarta la sesión y cierra con 1000. |
| servidor → juego | `bye` | `reason: "replaced"` (el mismo jugador entró desde otro dispositivo). |
| servidor → juego | `error` | `code` y `msg`; casi siempre sigue un cierre. |

**Códigos de cierre** (los de 4000 a 4999 son de la aplicación): `4000` reemplazado, `4001` versión distinta del
protocolo, `4002` mensaje inválido o demasiado grande, `4003` demasiados mensajes seguidos, `4004` demasiadas
conexiones, `4005` no llegó el saludo a tiempo, `1000` cierre normal. **El motivo también viaja escrito en el
cierre** (por ejemplo `bad_message`): Godot puede descartar un mensaje que llega justo antes del cierre, y esa
es la única parte que no se pierde (lo comprobó la prueba contra el servidor real).

## Reintentos y latido (cliente)

* Si no hay conexión, el cliente espera y reintenta: **1, 2, 4, 8, 16 y 30 s** (±20 % al azar para que muchos
  teléfonos no reintenten a la vez). Tras `4002` a `4005` la espera base es de 5 s. Hace como máximo 10
  reintentos seguidos y entonces muestra "No se pudo conectar" (el botón permite volver a intentarlo).
* Latido: manda `ping` cada 20 s y espera el `pong` hasta 10 s. Si el teléfono vuelve de segundo plano
  (`check_now()`), comprueba la conexión en 4 s. Si no hay respuesta, cuenta como conexión perdida y reintenta.
* Si el servidor cierra con `4001` (versión distinta) o `4000` (reemplazado), **no** reintenta.

## Límites del servidor

Protegen la cuota gratuita y a los demás jugadores. Están en `server/src/protocol.js`:

| Límite | Valor |
| --- | --- |
| Tamaño de un mensaje | 4 096 caracteres |
| Ráfaga y ritmo | 40 mensajes de golpe, 10 por segundo en adelante (cubeta de fichas) |
| Conexiones a la vez / sesiones guardadas | 300 / 600 |
| Conexiones por dirección de red | 20 (varias personas pueden compartir wifi o red móvil) |
| Plazo para saludar | 10 s |
| Mensajes inválidos tolerados después del saludo | 3 |

## Seguridad

* Solo se acepta `wss://` (conexión cifrada). `ws://` y `http://` únicamente hacia el propio dispositivo
  (`127.0.0.1`/`localhost`), para las pruebas automáticas.
* El servidor **no confía** en el cliente: valida el tamaño, el formato, la versión y el identificador de cada
  mensaje y corta a quien insiste.
* No se guardan datos personales: solo el identificador anónimo, el nombre que cada jugador elige y su código de
  sesión temporal.
* El APK **no lleva claves**. Lo único que viaja en él es la dirección pública del servidor (`data/online.json`).
  Las claves de Cloudflare viven solo como secretos de GitHub y las usa únicamente el flujo de despliegue.
* La llave con la que se firma el APK de prueba **nunca se sube al repositorio** (ver [Firma del APK de prueba](#firma-del-apk-de-prueba-actualizar-sin-desinstalar)).

## Firma del APK de prueba: actualizar sin desinstalar

Hasta la 0.3.0 cada compilación de GitHub creaba una llave de depuración nueva, y Android no deja instalar un
APK firmado con otra llave encima del anterior ("App no instalada"). Desde la 0.4.0-alfa.1 la llave se crea una
sola vez y se guarda en la caché de GitHub Actions (`llave-depuracion-v1`): solo la rama `main` la guarda y todas
las compilaciones la reutilizan. Consecuencias:

* **Una sola vez** hay que desinstalar la versión anterior (0.3.0 o menos) antes de instalar la 0.4.0-alfa.1; se
  pierde el progreso guardado en ese teléfono.
* A partir de ahí, cada APK nuevo se instala encima del anterior sin perder nada.
* GitHub borra las cachés que nadie usa durante 7 días. Si algún día pasara, la siguiente compilación de `main`
  crearía otra llave y habría que desinstalar de nuevo una vez más.
* La llave **nunca se sube al repositorio** (`.gitignore` ignora `*.keystore` y `*.jks`). Es una llave de
  depuración (su contraseña es pública): sirve para pruebas, **no** para publicar en Google Play.

## Qué comprobó la verificación automática

| Qué | Cómo |
| --- | --- |
| Lógica del servidor | 52 pruebas de Node (`server/test`): `HubCore` con reloj falso y el Durable Object con Cloudflare simulado (hibernación, alarmas, restauración de conexiones). |
| Servidor real en local | `wrangler dev` (el mismo motor de Cloudflare Workers, `workerd`) + 17 comprobaciones de extremo a extremo con conexiones WebSocket reales (`server/e2e/e2e.mjs`). |
| Juego contra ese servidor | Godot sin pantalla ejecuta `tools/online_e2e.gd`: 34 controles con `WebSocketPeer` real (conexión, latido, sesión reanudada tras un corte, reemplazo de dispositivo, despedida, errores del protocolo, servidor inexistente). |
| Cliente sin red | `tools/smoke_test.gd`: protocolo, configuración, reintentos, latido, códigos de cierre, y la pantalla MULTIJUGADOR con un transporte falso. |
| APK | Se comprueba el permiso `INTERNET`, la versión y la firma con `aapt2` y `apksigner`. |

## Lo que todavía **no** está comprobado

* **Teléfono real:** nada de esto se probó en un teléfono. Las pruebas corren en GitHub con render por software.
* **Servidor publicado en Cloudflare:** hasta que se haga el despliegue (ver
  [CONFIGURAR_SERVIDOR.md](CONFIGURAR_SERVIDOR.md)) el servidor solo se ha ejecutado en el emulador local de
  Cloudflare. El flujo de despliegue repite las pruebas contra el servidor publicado.
* **Conexión segura `wss://` desde Godot:** que el motor confíe en el certificado de Cloudflare solo se puede
  comprobar contra el servidor publicado (el flujo de despliegue lo hace). Los certificados son los habituales,
  así que se espera que funcione.
* **Cierre de conexiones que nunca saludan:** en `wrangler dev`, una conexión que no envía nada recibe el aviso
  `handshake_timeout` a los 10 s, pero el motor local tarda unos 10 s más en completar el cierre (hasta que el
  servidor "duerme"). El servidor la olvida enseguida. En producción puede ser distinto: el flujo de despliegue
  lo mide e informa.

## Decisiones para las fases siguientes

* Las **partidas** (4.2 y 4.3) serán autoritativas del servidor: el servidor decide el dado, valida los turnos y
  reparte el estado; el cliente solo pide y dibuja. Así nadie puede hacer trampa y se puede reanudar.
* Cuando haya partidas hará falta un **latido JSON** (no el `ping` de texto): Cloudflare contesta el `ping` sin
  despertar al servidor, así que el servidor no se entera de un cliente que se calló en medio de una partida.
* Una sola instancia del Durable Object (`principal`) atiende a todos hoy; con partidas habrá un objeto por
  sala, y el `Hub` pasará a ser solo el vestíbulo.
