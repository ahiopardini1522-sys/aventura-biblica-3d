class_name PlayerToken
extends Node3D
## Ficha provisional de un jugador: un peón de colores creado con primitivas.
## Cuando existan modelos reales en assets/models, solo hay que cambiar esta escena;
## el resto del juego únicamente usa setup(), character_id y set_bobbing().

const BOB_HEIGHT := 0.05
const BOB_TIME := 1.1

var character_id: String = ""

var _character: Dictionary = {}
var _bob_tween: Tween
var _bobbing: bool = true

@onready var _visual: Node3D = %Visual
@onready var _base: MeshInstance3D = %Base
@onready var _body: MeshInstance3D = %Body
@onready var _head: MeshInstance3D = %Head
@onready var _initial: Label3D = %Initial


func _ready() -> void:
	_apply()
	_update_bobbing()


## Configura la ficha con un personaje de CharacterCatalog (o una entrada de build_roster()).
func setup(character: Dictionary) -> void:
	_character = character
	character_id = str(character.get("character_id", character.get("id", "")))
	if is_node_ready():
		_apply()


## Activa o detiene el balanceo suave de reposo.
func set_bobbing(enabled: bool) -> void:
	_bobbing = enabled
	if is_node_ready():
		_update_bobbing()


func _apply() -> void:
	if _character.is_empty():
		return
	var color: Color = _character.get("color", Color.WHITE)
	_base.material_override = MeshFactory.material(color.darkened(0.4), 0.6)
	_body.material_override = MeshFactory.material(color, 0.55)
	_head.material_override = MeshFactory.material(color.lightened(0.28), 0.5)
	var display_name: String = str(_character.get("name", "?"))
	_initial.text = display_name.substr(0, 1).to_upper()
	_initial.modulate = color.lightened(0.55)


func _update_bobbing() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_visual.position = Vector3.ZERO
	if not _bobbing or not is_inside_tree():
		return
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_visual, "position:y", BOB_HEIGHT, BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_visual, "position:y", 0.0, BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
