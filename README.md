# AVENTURA BÍBLICA 3D

Juego de tablero 3D para Android con temática bíblica, hecho con **Godot 4.7** y **GDScript**.
Orientación horizontal, interfaz táctil y recursos provisionales creados por código, sin modelos externos.

> **Etapa 1 (esta versión):** estructura del proyecto, menú principal 3D, pantallas de navegación y escena de preparación del tablero.
> Las reglas del juego todavía **no** están implementadas (ver [Qué falta](#qué-falta)).

## Qué incluye la Etapa 1

| Pantalla | Qué hace |
| --- | --- |
| **Menú principal** | Título, paisaje 3D procedural del desierto con cielo, sol, colinas, río, palmeras y rocas, y animaciones suaves. Botones **JUGAR, MAPAS, MULTIJUGADOR, PERSONAJES, CONFIGURACIÓN**, todos con función. |
| **Mapas** | Lista los 6 mapas del catálogo (`data/maps/maps.json`). Solo *Desierto del Sinaí* está disponible; los demás se muestran bloqueados con la etiqueta "PRÓXIMAMENTE". |
| **Multijugador** | Elegir de 1 a 4 jugadores en el mismo dispositivo y empezar la partida. La sección en línea es solo informativa (sin botón). |
| **Personajes** | Seis personajes con vista 3D giratoria, descripción y referencia bíblica. El elegido se guarda. |
| **Configuración** | Volumen general, de música y de efectos, calidad gráfica (baja, media, alta), contador de FPS, sonido de prueba y restablecer. Los ajustes se guardan. |
| **Tablero 3D** | 100 casillas en serpentina numeradas, 6 escaleras, 7 serpientes, punto de inicio, meta, dado 3D que se puede lanzar, fichas de los jugadores en la salida, cámara con giro, zoom y vista inicial, e iluminación con sombras. |

Controles del tablero: un dedo arrastra para girar la cámara, el gesto de pellizco acerca o aleja (también hay botones **+** y **−**) y el botón **VISTA** restaura la cámara. **LANZAR DADO** tira el dado y **MENÚ** vuelve al menú principal. En Android, el botón o gesto de atrás vuelve al menú principal desde cualquier pantalla y, estando en el menú, cierra el juego.

## Estructura

```
aventura-biblica-3d/
├── project.godot            Configuración del proyecto (escena principal, autoloads, Android)
├── export_presets.cfg       Preajuste de exportación a Android (APK de depuración, arm64)
├── icon.svg                 Ícono de la aplicación
├── scenes/
│   ├── menus/               Menú principal y pantallas (mapas, multijugador, personajes, ajustes)
│   ├── boards/              Escena del tablero y dado
│   ├── characters/          Ficha del jugador y vista previa 3D
│   ├── maps/                Entorno 3D de cada mapa
│   ├── interfaces/          Cabecera de pantallas y panel del tablero (HUD)
│   └── challenges/          Reservada para las preguntas (etapa posterior)
├── scripts/
│   ├── game/                Autoloads: SettingsManager, GameState, SceneRouter; sonido y datos
│   ├── dice/                Dado 3D
│   ├── players/             Catálogo de personajes, ficha y vista previa
│   ├── questions/           Banco de preguntas (carga datos, aún sin interfaz)
│   ├── maps/                Catálogo de mapas, constructor del tablero, paisajes y props
│   └── ui/                  Tema visual, efectos y controladores de pantallas
├── assets/                  models/ textures/ audio/ fonts/ (vacías: todo es provisional por código)
├── data/
│   ├── maps/maps.json                  Definición de mapas, escaleras y serpientes
│   ├── questions/sample_questions.json Preguntas de ejemplo
│   └── verses/verse_references.json    Referencias bíblicas (solo citas, sin texto)
├── tools/                   Pruebas automáticas (prueba de humo y capturas)
└── .github/                 Compilación y verificación automática en GitHub Actions
```

### Autoloads

* `SettingsManager`: volúmenes, calidad gráfica, FPS; guarda en `user://settings.cfg`.
* `GameState`: mapa, personaje y número de jugadores elegidos; guarda en `user://profile.cfg`.
* `SceneRouter`: navegación entre pantallas con transición, rutas centralizadas y botón de atrás de Android.

## Cómo ejecutar el proyecto

1. Instala **Godot 4.7.x** (versión estable, edición estándar, no .NET): <https://godotengine.org/download>.
2. Abre Godot, pulsa **Importar** y elige el archivo `project.godot` de este repositorio.
3. Espera a que termine la primera importación y pulsa **F5** (Ejecutar proyecto).

El proyecto usa el renderizador **Compatibilidad** (OpenGL), pensado para funcionar bien en móviles de gama media.

## Cómo probarlo en Android

### Opción A: APK generado automáticamente (no necesita computadora)

1. En GitHub abre la pestaña **Actions** del repositorio y entra a la última ejecución de **Compilar y verificar** que haya terminado en verde.
2. Descarga el artefacto **aventura-biblica-3d-apk-debug** (llega comprimido en `.zip`; descomprímelo con el administrador de archivos del móvil).
3. Cuando la rama `main` se compila, el mismo APK queda también en **Releases**, en el pre-lanzamiento **latest-debug**.
4. Abre el `.apk` en el teléfono y permite la instalación de apps desconocidas cuando Android lo pida.

### Opción B: exportar desde el editor de Godot

1. En Godot: **Editor → Administrar plantillas de exportación** y descarga las de 4.7.x.
2. En **Editor → Configuración del editor → Exportar → Android** indica el SDK de Android y el JDK 17.
3. En **Proyecto → Exportar** elige el preajuste **Android** y pulsa **Exportar proyecto** (o conecta el teléfono con depuración USB y usa **Despliegue con un clic**).

El preajuste ya trae: paquete `com.aventurabiblica.game3d`, arquitectura arm64-v8a, sin Gradle, pantalla horizontal, modo inmersivo y sin permisos extra.

## Verificación automática

El flujo `.github/workflows/build.yml` ejecuta en cada subida de código, con Godot real:

1. **validar**: importa el proyecto, compila los scripts y ejecuta `tools/smoke_test.gd` (carga todas las escenas, comprueba rutas `res://`, datos, tablero de 100 casillas, escaleras, serpientes, dado y navegación).
2. **capturas**: abre cada pantalla con una pantalla virtual y guarda imágenes.
3. **android**: exporta el APK de depuración con las plantillas oficiales y revisa su contenido con `aapt2`.
4. **resumen**: deja los registros y las imágenes en la rama `ci-artifacts`.

El resultado de cada ejecución (verde o rojo) se ve en la pestaña **Actions**. Un APK solo existe si el paso de exportación terminó bien.

## Datos y cómo ampliar

* **Nuevo mapa:** añade una entrada en `data/maps/maps.json` (tamaño del tablero, escaleras, serpientes, colores y props) y cambia su `status` a `"available"` cuando esté listo. El tablero se construye a partir de esos datos.
* **Nuevas preguntas:** añade objetos a `data/questions/` con el mismo formato que `sample_questions.json`.
* **Modelos reales:** coloca los archivos en `assets/models/` y sustituye el recurso provisional correspondiente (fichas en `scenes/characters/`, props en `scripts/maps/prop_factory.gd`).

## Qué falta

* Turnos y movimiento de las fichas por el tablero.
* Subir por escaleras y bajar por serpientes al caer en ellas.
* Preguntas bíblicas en pantalla (el banco de preguntas ya carga datos, falta la interfaz y las reglas).
* Mapas bíblicos adicionales con sus modelos y texturas.
* Multijugador en línea (la estructura de jugadores ya admite varios; falta la red).
* Música ambiental y modelos 3D definitivos.
* Exportación firmada para Google Play (hoy solo hay APK de depuración).

## Licencia

Aún sin definir. Hasta que se indique otra cosa, todos los derechos están reservados por el autor del repositorio.
