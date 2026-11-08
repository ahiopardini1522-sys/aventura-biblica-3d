# Conectar el servidor en línea (guía para hacerlo solo desde el teléfono)

El juego en línea necesita un pequeño servidor. Está hecho para **Cloudflare Workers** (plan gratuito) y se publica
solo, desde GitHub: **no hace falta computadora ni instalar nada**. Tú solo creas la cuenta de Cloudflare, copias dos
datos a GitHub y pulsas un botón. Tiempo aproximado: 15 a 20 minutos la primera vez.

> **Qué está comprobado y qué no.** El servidor y el cliente del juego se probaron de verdad en GitHub Actions contra
> `wrangler dev` (el mismo motor que usa Cloudflare), pero **todavía no se publicó en Cloudflare**, porque eso necesita
> tu cuenta. La primera ejecución del flujo "Desplegar servidor en línea" es la primera prueba real contra Cloudflare.
> Por eso el flujo está hecho para parar con mensajes claros si algo falla (ver [Problemas frecuentes](#problemas-frecuentes)).
> Además, los nombres de los menús de Cloudflare y de GitHub cambian de vez en cuando y **esta guía no se pudo
> contrastar con el panel de Cloudflare en vivo**: si algún nombre no coincide, busca el parecido y, si te atascas, mándame
> una captura.

## Lo que vas a necesitar

* Un correo electrónico y el navegador del teléfono (Chrome, por ejemplo). Para GitHub, **mejor el navegador que la
  app**: la app de GitHub no muestra todos los ajustes del repositorio.
* La cuenta de GitHub dueña del repositorio `aventura-biblica-3d`.
* Que el código de la Etapa 4 ya esté en la rama `main` (el botón "Run workflow" solo aparece para los flujos que están en
  `main`). Si el botón no aparece, avísame.

## Paso 1. Crear la cuenta de Cloudflare (gratis)

1. Abre <https://dash.cloudflare.com/sign-up> y regístrate con tu correo y una contraseña.
2. Confirma el correo (te llega un mensaje con un enlace).
3. Si Cloudflare te ofrece "añadir un sitio" o un dominio, **no hace falta**: puedes saltarlo. El servidor usa una
   dirección gratuita que termina en `workers.dev`.
4. Hasta donde sé, el plan gratuito no pide tarjeta. **Si Cloudflare te pidiera una tarjeta o un pago, detente y
   avísame** antes de seguir.

## Paso 2. Crear el token de API

El token es la "llave" con la que GitHub publicará el servidor en tu cuenta. Solo puede editar Workers.

1. Entra en <https://dash.cloudflare.com/profile/api-tokens> (o toca tu perfil, arriba a la derecha → **My Profile**
   → **API Tokens**).
2. Toca **Create Token**.
3. En la lista de plantillas elige **Edit Cloudflare Workers** y toca **Use template**.
4. Revisa que en *Account Resources* aparezca **tu cuenta**. Si pide algo de *Zone Resources* (zonas o dominios) y no
   tienes ninguno, déjalo como viene.
5. Toca **Continue to summary** y luego **Create Token**.
6. Cloudflare muestra el token **una sola vez**. Cópialo ahora (botón **Copy**) y pégalo en un lugar seguro y temporal,
   por ejemplo una nota privada del teléfono, hasta terminar el paso 4.

## Paso 3. Encontrar el "Account ID"

Es un código de 32 letras y números (de `0` a `9` y de `a` a `f`) que identifica tu cuenta.

* **Forma más fácil:** entra en <https://dash.cloudflare.com>; cuando se abre el panel, mira la **barra de direcciones**
  del navegador: la dirección tiene la forma `https://dash.cloudflare.com/` + **el código de 32 caracteres** + `/home`.
  Ese código es tu Account ID.
* **Otra forma:** en el panel, entra en **Workers & Pages**; el *Account ID* aparece en esa página (en el teléfono, a
  veces al final de la pantalla) con un botón para copiarlo.

## Paso 4. Guardar los dos secretos en GitHub

Esto se hace en el navegador del teléfono. Si no ves el menú, activa **Sitio de escritorio** en las opciones del navegador.

1. Abre <https://github.com/ahiopardini1522-sys/aventura-biblica-3d/settings/secrets/actions>
   (o: el repositorio → **Settings** → **Secrets and variables** → **Actions**).
2. Toca **New repository secret**.
   * **Name:** `CLOUDFLARE_API_TOKEN` (exactamente así, en mayúsculas)
   * **Secret:** pega el token del paso 2
   * Toca **Add secret**.
3. Otra vez **New repository secret**.
   * **Name:** `CLOUDFLARE_ACCOUNT_ID`
   * **Secret:** pega el Account ID del paso 3
   * Toca **Add secret**.

Después de guardarlos, GitHub **ya no te los vuelve a mostrar** (es normal). Borra la nota temporal donde copiaste el token.

## Paso 5. Publicar el servidor

1. Abre <https://github.com/ahiopardini1522-sys/aventura-biblica-3d/actions/workflows/servidor-desplegar.yml>
   (o: pestaña **Actions** → en la lista de flujos, **Desplegar servidor en línea**; en el teléfono la lista está tras el
   botón **All workflows**).
2. Toca **Run workflow**, deja **Branch: main** y toca el botón verde **Run workflow**.
3. Espera entre 3 y 6 minutos. Toca la ejecución nueva para ver los pasos.

Qué hace el flujo, en orden (todo automático):

1. Comprueba que existan los dos secretos. Si faltan, termina **sin error** y lo explica en su resumen.
2. Instala `wrangler` (la herramienta oficial de Cloudflare) y pasa las pruebas del servidor (52 hoy).
3. Prepara el subdominio gratuito `workers.dev` de tu cuenta (lo crea si todavía no existe).
4. Publica el servidor (`wrangler deploy`).
5. Espera a que `…/health` responda.
6. Repite las **pruebas de extremo a extremo** (17 hoy) contra el servidor ya publicado.
7. Prueba el cliente de Godot por conexión segura (`wss://`). Este paso **no bloquea** el despliegue: si falla, queda
   anotado en el resumen.
8. Guarda la dirección del servidor en `data/online.json`, la sube a `main` y **vuelve a compilar la app**.

## Paso 6. Comprobar que funcionó

1. En la ejecución terminada, toca **Summary** (arriba a la izquierda). Debe decir **Despliegue: success** y mostrar la
   **Dirección** del servidor, algo como `https://aventura-biblica-online.TU-SUBDOMINIO.workers.dev`.
2. Abre esa dirección y añade `/health` al final en el navegador del teléfono. Debe responder un texto parecido a
   `{"ok":true,"service":"aventura-biblica-online", …}`.
3. A los 6 a 8 minutos de terminar el despliegue, abre **Releases** del repositorio: aparece un APK nuevo
   (`aventura-biblica-3d-v0.4.0-alfa.1-debug.apk` y `latest-debug`) que ya lleva la dirección del servidor.

## Paso 7. Instalar el APK nuevo

1. **Solo esta vez, desinstala la versión anterior** (la 0.3.0 o menor). Hasta ahora cada compilación usaba una llave de
   firma distinta, y Android no deja instalar encima una app firmada con otra llave. Se pierden los ajustes y el progreso
   guardados en ese teléfono.
2. Descarga e instala el APK nuevo (permite la instalación de apps desconocidas si Android lo pide).
3. **Desde esta versión** los APK de prueba se firman con una llave que se guarda y se reutiliza, así que los siguientes
   se instalan encima sin desinstalar. Una excepción: GitHub borra las cachés que nadie usa durante 7 días; si eso pasara,
   la siguiente compilación crearía otra llave y habría que desinstalar una vez más (ver
   [la sección de firma](ARQUITECTURA.md#firma-del-apk-de-prueba-actualizar-sin-desinstalar)).

## Paso 8. Probar la conexión en el juego

1. Abre el juego → **MULTIJUGADOR**. A la derecha está el panel **PARTIDA EN LÍNEA**.
2. Toca **PROBAR CONEXIÓN**. Debe pasar por *Conectando…* y quedar en **Conectado · 1 jugador en línea** (con un punto
   verde). Si hay otro teléfono conectado a la vez, dirá 2.
3. **DESCONECTAR** corta la conexión. Al salir de la pantalla la conexión se cierra sola.

Si el panel sigue diciendo *Servidor en línea sin configurar*, ese APK es anterior al despliegue: descarga el más reciente
de **Releases**.

> Por ahora la conexión solo sirve para comprobar que el teléfono y el servidor se entienden. Las salas, los códigos de
> invitación, los oponentes al azar y los turnos sincronizados llegan en las fases 4.2 y 4.3, y **no se empiezan sin tu
> visto bueno**.

## Problemas frecuentes

| Qué ves | Qué significa y qué hacer |
| --- | --- |
| El resumen dice *"todavía falta conectar Cloudflare"* | Faltan secretos o el nombre está mal escrito. Revisa que existan `CLOUDFLARE_API_TOKEN` y `CLOUDFLARE_ACCOUNT_ID` (mayúsculas exactas, sin espacios) y vuelve a ejecutar. No es un error del código. |
| *"No se pudo obtener ni crear el subdominio workers.dev"* | El token no tiene permisos o el Account ID es de otra cuenta. Crea el token de nuevo con la plantilla **Edit Cloudflare Workers**, comprueba que el Account ID sea el de la barra de direcciones y vuelve a guardar los dos secretos. |
| Error de autenticación en `wrangler deploy` (por ejemplo "Authentication error") | Token mal copiado, caducado o sin permisos. Crea otro y reemplaza el secreto (en GitHub, abrir el secreto y tocar **Update**). |
| *"El servidor publicado no respondió en 3 minutos"* | A veces una dirección nueva tarda en resolverse. Espera unos minutos y vuelve a ejecutar el flujo. Si se repite, revisa en Cloudflare → **Workers & Pages** que exista `aventura-biblica-online`. |
| Falla "Pruebas de extremo a extremo" | Copia el nombre de la prueba que falló y el mensaje, y mándamelos. No se publica la dirección en el juego mientras esto falle. |
| "Prueba del cliente por wss://" en rojo, pero lo demás en verde | El despliegue siguió, pero ese aviso significa que Godot podría no confiar en el certificado de Cloudflare. Mándame el registro del paso antes de usar el APK. |
| En el juego: *"No se pudo conectar. Revisa tu conexión a Internet…"* | Revisa que el teléfono tenga Internet y que el APK sea el posterior al despliegue. Pulsa de nuevo PROBAR CONEXIÓN. |
| En el juego: *"Tu versión del juego no coincide con la del servidor. Actualiza la app."* | El servidor y el juego hablan versiones distintas del protocolo. Instala el APK más reciente. |

## Costos y límites

* El plan gratuito de Cloudflare tiene límites de uso. **No pude consultar las cifras vigentes** ni comprobar qué pasa al
  superarlas, así que no te doy números: revísalos en la página de precios de Cloudflare antes de invitar a mucha gente y
  **no registres tarjeta ni cambies de plan sin leer las condiciones**.
* El servidor está hecho para gastar poco: limita por su cuenta las conexiones (300 a la vez, 20 por dirección de
  Internet) y el ritmo de mensajes, y "duerme" cuando nadie lo usa (ver [ARQUITECTURA.md](ARQUITECTURA.md#límites-del-servidor)).

## Seguridad

* **Nunca pegues el token ni el Account ID en el chat, en un archivo del repositorio ni en una captura.** Solo viven como
  secretos de GitHub. El APK **no** lleva ningún secreto: solo la dirección pública del servidor, que no es una
  contraseña.
* Si crees que el token se filtró: en Cloudflare, **API Tokens** → el token → **Roll** (o **Delete**), crea otro y
  actualiza el secreto en GitHub.
* El servidor no guarda cuentas, correos ni contraseñas: cada teléfono genera un identificador anónimo al azar.

## Apagar o cambiar el servidor

* **Apagar:** en Cloudflare → **Workers & Pages** → `aventura-biblica-online` → **Settings** → eliminar el Worker. El juego
  sigue funcionando sin partidas en línea (mostrará que no se pudo conectar).
* **Volver a publicar:** repite el paso 5. Se puede ejecutar cuantas veces haga falta. También se ejecuta solo cuando
  alguien cambia algo de la carpeta `server/` en `main`.
* **Cambiar de cuenta de Cloudflare:** crea el token y el Account ID de la cuenta nueva, reemplaza los dos secretos y
  repite el paso 5. La dirección nueva reemplaza a la anterior en `data/online.json`.
