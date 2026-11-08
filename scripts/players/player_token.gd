class_name PlayerToken
extends Node3D
## Ficha provisional de un jugador: un peón de colores creado con primitivas.
## Cuando existan modelos reales en assets/models, solo hay que cambiar esta escena;
## el resto del juego únicamente usa setup(), character_id, set_bobbing(), set_active(),
## set_tile_badge(), hop_to(), travel_path(), celebrate() y shake_head().

const BOB_HEIGHT := 0.05
const BOB_TIME := 1.1
const HOP_HEIGHT := 0.42

var character_id: String = ""

var _character: Dictionary = {}
var _color: Color = Color.WHITE
var _bob_tween: Tween
var _marker_tween: Tween
var _ring_tween: Tween
var _move_tween: Tween
var _squash_tween: Tween
var _bobbing: bool = true
var _active: bool = false
var _marker_root: Node3D
var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _badge: Label3D
## Datos del recorrido en curso (travel_path).
var _path_points: PackedVector3Array = PackedVector3Array()
var _path_lengths: PackedFloat32Array = PackedFloat32Array()
var _path_total: float = 0.0
var _path_lift: float = 0.0
var _path_bobs: int = 0

@onready var _visual: Node3D = %Visual
@onready var _base: MeshInstance3D = %Base
@onready var _body: MeshInstance3D = %Body
@onready var _head: MeshInstance3D = %Head
@onready var _initial: Label3D = %Initial


func _ready() -> void:
	_build_markers()
	_apply()
	_update_bobbing()
	set_active(_active)


## Configura la ficha con un personaje de CharacterCatalog (o una entrada de build_roster()).
func setup(character: Dictionary) -> void:
	_character = character
	character_id = str(character.get("character_id", character.get("id", "")))
	_color = character.get("color", Color.WHITE)
	if is_node_ready():
		_apply()
		_tint_markers()


## Activa o detiene el balanceo suave de reposo.
func set_bobbing(enabled: bool) -> void:
	_bobbing = enabled
	if is_node_ready():
		_update_bobbing()


## Marca esta ficha como la del turno actual: aro de luz, flecha que salta y número de casilla.
func set_active(active: bool) -> void:
	_active = active
	if not is_node_ready():
		return
	_marker_root.visible = active
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	if active and is_inside_tree():
		_marker_tween = create_tween().set_loops()
		_marker_tween.tween_property(_arrow, "position:y", 1.34, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_marker_tween.tween_property(_arrow, "position:y", 1.2, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ring_tween = create_tween().set_loops()
		_ring_tween.tween_property(_ring, "scale", Vector3(1.18, 1.0, 1.18), 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ring_tween.tween_property(_ring, "scale", Vector3.ONE, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func is_active() -> bool:
	return _active


## Número que flota sobre la ficha (la casilla en la que está).
func set_tile_badge(tile: int) -> void:
	if _badge != null:
		_badge.text = str(tile)


func badge_text() -> String:
	return _badge.text if _badge != null else ""


## Muestra u oculta la letra inicial sobre la cabeza (en el podio ya se ve el nombre completo).
func set_initial_visible(shown: bool) -> void:
	if is_node_ready():
		_initial.visible = shown


## Salto de una casilla a otra. Devuelve el Tween para poder esperar su "finished".
func hop_to(destination: Vector3, duration: float, height: float = HOP_HEIGHT) -> Tween:
	_stop_move()
	var origin: Vector3 = position
	var lift: float = height
	_move_tween = create_tween()
	_move_tween.tween_method(_set_hop.bind(origin, destination, lift), 0.0, 1.0, maxf(duration, 0.001))
	_move_tween.finished.connect(_squash.bind(maxf(duration, 0.001)))
	return _move_tween


## Recorre una línea quebrada (escalera o cuerpo de una serpiente). "bobs" son los saltitos
## que da por el camino (uno por peldaño) y "lift" lo que sube sobre la línea.
func travel_path(points: PackedVector3Array, duration: float, bobs: int = 0,
		bob_height: float = 0.1, lift: float = 0.0) -> Tween:
	_stop_move()
	_path_points = points
	_path_lengths = PackedFloat32Array([0.0])
	_path_total = 0.0
	for i in range(1, points.size()):
		_path_total += points[i - 1].distance_to(points[i])
		_path_lengths.append(_path_total)
	_path_bobs = bobs
	_path_lift = lift
	_move_tween = create_tween()
	_move_tween.tween_method(_set_path.bind(bob_height), 0.0, 1.0, maxf(duration, 0.001))
	_move_tween.finished.connect(_squash.bind(maxf(duration, 0.001)))
	return _move_tween


## Saltitos de alegría en el sitio. Devuelve el Tween.
func celebrate(jumps: int = 3, duration: float = 0.9) -> Tween:
	_stop_move()
	var origin: Vector3 = position
	_move_tween = create_tween()
	var each: float = maxf(duration, 0.01) / float(maxi(jumps, 1))
	for _jump in jumps:
		_move_tween.tween_property(self, "position:y", origin.y + 0.55, each * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(self, "position:y", origin.y, each * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return _move_tween


## Movimiento de cabeza hacia los lados (respuesta equivocada). Devuelve el Tween.
func shake_head(duration: float = 0.5) -> Tween:
	var tween: Tween = create_tween()
	var each: float = maxf(duration, 0.01) / 6.0
	for angle in [0.35, -0.35, 0.25, -0.25, 0.12, 0.0]:
		tween.tween_property(_visual, "rotation:z", float(angle), each)
	return tween


## Detiene cualquier movimiento en curso y deja la ficha en su posición actual.
func stop_moving() -> void:
	_stop_move()


func _stop_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()


func _set_hop(progress: float, origin: Vector3, destination: Vector3, lift: float) -> void:
	var flat: Vector3 = origin.lerp(destination, progress)
	flat.y += lift * 4.0 * progress * (1.0 - progress)
	position = flat


func _set_path(progress: float, bob_height: float) -> void:
	if _path_points.size() < 2 or _path_total <= 0.0:
		return
	var distance: float = progress * _path_total
	var index: int = 1
	while index < _path_points.size() - 1 and _path_lengths[index] < distance:
		index += 1
	var segment_start: float = _path_lengths[index - 1]
	var segment_length: float = maxf(_path_lengths[index] - segment_start, 0.0001)
	var t: float = clampf((distance - segment_start) / segment_length, 0.0, 1.0)
	var point: Vector3 = _path_points[index - 1].lerp(_path_points[index], t)
	point.y += _path_lift
	if _path_bobs > 0:
		point.y += absf(sin(progress * PI * float(_path_bobs))) * bob_height
	position = point


## Aplasta la ficha un instante al caer, como un peón de goma.
func _squash(duration: float) -> void:
	if not is_inside_tree():
		return
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_visual.scale = Vector3(1.12, 0.82, 1.12)
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE, minf(0.18, maxf(duration, 0.02))) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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


## Aro de luz en el suelo, flecha sobre la cabeza y número de casilla: se ven solo en la ficha activa.
func _build_markers() -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "TurnMarker"
	_marker_root.visible = false
	add_child(_marker_root)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.36
	ring_mesh.outer_radius = 0.46
	ring_mesh.rings = 28
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = ring_mesh
	_ring.scale = Vector3.ONE
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.05, 0.0)
	_marker_root.add_child(_ring)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.17
	cone.height = 0.34
	cone.radial_segments = 4
	cone.rings = 1
	_arrow = MeshInstance3D.new()
	_arrow.name = "Arrow"
	_arrow.mesh = cone
	_arrow.rotation = Vector3(PI, 0.0, 0.0)
	_arrow.position = Vector3(0.0, 1.2, 0.0)
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_root.add_child(_arrow)

	_badge = Label3D.new()
	_badge.name = "TileBadge"
	_badge.text = "1"
	_badge.font_size = 96
	_badge.pixel_size = 0.0068
	_badge.outline_size = 22
	_badge.outline_modulate = Color(0.10, 0.06, 0.02, 0.96)
	_badge.modulate = Color(1.0, 0.92, 0.55)
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.no_depth_test = true
	_badge.shaded = false
	_badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_badge.position = Vector3(0.0, 1.68, 0.0)
	_marker_root.add_child(_badge)
	_tint_markers()


func _tint_markers() -> void:
	if _ring == null:
		return
	_ring.material_override = MeshFactory.glow_material(Color(_color.lightened(0.25), 0.9))
	_arrow.material_override = MeshFactory.glow_material(Color(_color.lightened(0.4), 0.95))
