extends Node
## Autoload "SceneRouter": navegación entre pantallas con fundido y
## detalles globales de interfaz (tema visual, sonido y animación de botones).

signal scene_changed(key: String)

## Todas las pantallas del juego. Cada clave se usa con SceneRouter.go_to("clave").
const SCENES: Dictionary = {
	"main_menu": "res://scenes/menus/main_menu.tscn",
	"world": "res://scenes/menus/world_screen.tscn",
	"maps": "res://scenes/menus/maps_screen.tscn",
	"multiplayer": "res://scenes/menus/multiplayer_screen.tscn",
	"characters": "res://scenes/menus/characters_screen.tscn",
	"settings": "res://scenes/menus/settings_screen.tscn",
	"board": "res://scenes/boards/board_scene.tscn",
	"victory": "res://scenes/boards/victory_scene.tscn",
}
## A dónde lleva "volver" desde cada pantalla (las que no están aquí vuelven al menú principal).
const BACK_TARGETS: Dictionary = {
	"maps": "world",
}
const FADE_TIME := 0.22
const FADE_COLOR := Color(0.03, 0.04, 0.09)

var current_key: String = "main_menu"
var is_transitioning: bool = false

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UiTheme.build()
	_build_fade_overlay()
	get_tree().node_added.connect(_on_node_added)
	_fade_in_at_start()


## Cambia a la pantalla indicada (clave de SCENES) con un fundido.
func go_to(key: String) -> void:
	if is_transitioning:
		return
	if not SCENES.has(key):
		push_error("SceneRouter: pantalla desconocida '%s'" % key)
		return
	var path: String = SCENES[key]
	if not ResourceLoader.exists(path):
		push_error("SceneRouter: no existe %s" % path)
		return
	is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var fade_out: Tween = create_tween()
	fade_out.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	await fade_out.finished
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: no se pudo abrir %s (error %d)" % [path, err])
	else:
		current_key = key
	await get_tree().process_frame
	await get_tree().process_frame
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)
	await fade_in.finished
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	scene_changed.emit(key)


func go_back() -> void:
	go_to(str(BACK_TARGETS.get(current_key, "main_menu")))


func quit_game() -> void:
	get_tree().quit()


func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(FADE_COLOR, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


func _fade_in_at_start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, 0.5)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		UiFx.polish_button(node)
	# Las interfaces cuelgan de una CanvasLayer; se les asigna el tema de forma directa
	# para no depender de cómo se hereda el tema a través de esa capa.
	if node is Control and node.get_parent() is CanvasLayer:
		(node as Control).theme = UiTheme.build()
