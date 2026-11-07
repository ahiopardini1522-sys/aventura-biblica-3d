class_name Dice
extends Node3D
## Dado 3D de seis caras. roll() lo hace saltar y girar y termina mostrando el número elegido.
## Etapa 1: solo muestra el resultado; el uso del número en el juego llega en otra etapa.

signal roll_started
signal roll_finished(value: int)

const SIZE := 1.1
const ROLL_TIME := 1.3
const HOP_HEIGHT := 2.2
const FACE_OFFSET := 0.004
## Rotación (Euler, orden YXZ de Godot) que deja cada cara hacia arriba.
const FACE_ROTATIONS := {
	1: Vector3(0.0, 0.0, 0.0),
	2: Vector3(-PI * 0.5, 0.0, 0.0),
	3: Vector3(0.0, 0.0, PI * 0.5),
	4: Vector3(0.0, 0.0, -PI * 0.5),
	5: Vector3(PI * 0.5, 0.0, 0.0),
	6: Vector3(PI, 0.0, 0.0),
}
## Hacia dónde mira cada cara en reposo. Las caras opuestas suman 7.
const FACE_NORMALS := {
	1: Vector3(0.0, 1.0, 0.0),
	6: Vector3(0.0, -1.0, 0.0),
	2: Vector3(0.0, 0.0, 1.0),
	5: Vector3(0.0, 0.0, -1.0),
	3: Vector3(1.0, 0.0, 0.0),
	4: Vector3(-1.0, 0.0, 0.0),
}

var is_rolling: bool = false
var last_value: int = 1

var _rest_y: float = SIZE * 0.5

@onready var _body: Node3D = %Body


func _ready() -> void:
	_build_body()
	_body.position = Vector3(0.0, _rest_y, 0.0)
	_body.rotation = Vector3(0.0, 0.5, 0.0)


## Lanza el dado. Si "forced_value" está entre 1 y 6 sale ese número (útil para pruebas);
## si no, sale uno al azar. Devuelve el número que saldrá, o 0 si ya estaba rodando.
func roll(forced_value: int = 0) -> int:
	if is_rolling:
		return 0
	var value: int = forced_value if forced_value >= 1 and forced_value <= 6 else randi_range(1, 6)
	is_rolling = true
	last_value = value
	roll_started.emit()
	SettingsManager.play_dice()

	var face: Vector3 = FACE_ROTATIONS[value]
	var final_rotation := Vector3(face.x, randf_range(0.0, TAU), face.z)
	var spins := Vector3(
			TAU * float(randi_range(2, 3)) * (1.0 if randf() < 0.5 else -1.0),
			TAU * float(randi_range(1, 2)) * (1.0 if randf() < 0.5 else -1.0),
			TAU * float(randi_range(2, 3)) * (1.0 if randf() < 0.5 else -1.0))

	var spin: Tween = create_tween()
	spin.tween_property(_body, "rotation", final_rotation + spins, ROLL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var hop: Tween = create_tween()
	hop.tween_property(_body, "position:y", _rest_y + HOP_HEIGHT, ROLL_TIME * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(_body, "position:y", _rest_y, ROLL_TIME * 0.6) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	hop.finished.connect(_on_roll_finished.bind(value, final_rotation))
	return value


## Número que está mirando hacia arriba en este momento.
func up_face() -> int:
	var best_value: int = 1
	var best_dot: float = -2.0
	for value in FACE_NORMALS:
		var local_normal: Vector3 = FACE_NORMALS[value]
		var world_normal: Vector3 = _body.global_transform.basis * local_normal
		var dot: float = world_normal.normalized().dot(Vector3.UP)
		if dot > best_dot:
			best_dot = dot
			best_value = int(value)
	return best_value


func _on_roll_finished(value: int, final_rotation: Vector3) -> void:
	_body.rotation = final_rotation
	_body.position.y = _rest_y
	is_rolling = false
	roll_finished.emit(value)


## Cubo de marfil con los números de cada cara.
func _build_body() -> void:
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(SIZE, SIZE, SIZE)
	var cube := MeshInstance3D.new()
	cube.name = "Cube"
	cube.mesh = cube_mesh
	cube.material_override = MeshFactory.material(Color(0.97, 0.94, 0.85), 0.4)
	_body.add_child(cube)

	for value in FACE_NORMALS:
		var normal: Vector3 = FACE_NORMALS[value]
		var up_hint: Vector3 = Vector3.UP
		if absf(normal.y) > 0.5:
			up_hint = Vector3(0.0, 0.0, -1.0) if normal.y > 0.0 else Vector3(0.0, 0.0, 1.0)
		var label := Label3D.new()
		label.name = "Face%d" % int(value)
		label.text = str(int(value))
		label.font_size = 96
		label.pixel_size = 0.0085
		label.shaded = false
		label.double_sided = false
		label.modulate = Color(0.52, 0.07, 0.05)
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.transform = Transform3D(Basis.looking_at(-normal, up_hint),
				normal * (SIZE * 0.5 + FACE_OFFSET))
		_body.add_child(label)
