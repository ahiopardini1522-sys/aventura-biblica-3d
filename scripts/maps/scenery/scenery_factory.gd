class_name SceneryFactory
extends RefCounted
## Elige y construye el escenario 3D de un mapa según su "style" de data/maps/maps.json.
## El Desierto del Sinaí ("desierto") conserva su decoración original y no pasa por aquí.

const STYLES: Array[String] = ["eden", "arca", "egipto", "sinai", "jerusalen", "belen"]


## Verdadero si el estilo tiene un escenario propio (con su terreno, que reemplaza el suelo liso).
static func has_scenery(style: String) -> bool:
	return STYLES.has(style)


## Construye el escenario dentro de "root". "quality" es SettingsManager.Quality (0, 1 o 2).
static func build(style: String, root: Node3D, seed_value: int, quality: int, theme_data: Dictionary) -> void:
	var ground: Color = Color(0.40, 0.62, 0.30)
	var raw: Variant = theme_data.get("ground", ground)
	if raw is Color:
		ground = raw
	match style:
		"eden":
			SceneryEden.build(root, seed_value, quality, ground)
