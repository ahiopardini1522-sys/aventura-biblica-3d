class_name Dice
extends Node3D
## Dado 3D de seis caras. roll() lo lanza al aire, lo hace girar y rebotar y termina
## mostrando el número elegido. Mientras rueda ignora nuevos lanzamientos.

signal roll_started
signal roll_finished(value: int)

const SIZE := 1.1
const ROLL_TIME := 1.45
const HOP_HEIGHT := 2.4
const DRIFT := 0.45
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
## Velocidad de la animación (1 = normal). Las pruebas automáticas la suben.
var speed: float = 1.0

var _rest_y: float = SIZE * 0.5
var _shadow: MeshInstance3D
var _tweens: Array[Tween] = []

@onready var _body: Node3D = %Body


func _ready() -> void:
	_build_body()
	_build_shadow()
	_body.position = Vector3(0.0, _rest_y, 0.0)
	_body.rotation = Vector3(0.0, 0.5, 0.0)
	set_process(false)


func _process(_delta: float) -> void:
	_update_shadow()


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
	set_process(true)

	var total: float = ROLL_TIME / maxf(speed, 0.01)
	var face: Vector3 = FACE_ROTATIONS[value]
	var final_rotation := Vector3(face.x, randf_range(0.0, TAU), face.z)
	var spins := Vector3(
			TAU * float(randi_range(2, 3)) * (1.0 if randf() < 0.5 else -1.0),
			TAU * float(randi_range(1, 2)) * (1.0 if randf() < 0.5 else -1.0),
			TAU * float(randi_range(2, 3)) * (1.0 if randf() < 0.5 else -1.0))

	_clear_tweens()
	var spin: Tween = create_tween()
	_tweens.append(spin)
	spin.tween_property(_body, "rotation", final_rotation + spins, total) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Deriva suave hacia un punto cualquiera del pedestal.
	var drift: Tween = create_tween().set_parallel(true)
	_tweens.append(drift)
	var target := Vector2(randf_range(-DRIFT, DRIFT), randf_range(-DRIFT, DRIFT))
	drift.tween_property(_body, "position:x", target.x, total * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drift.tween_property(_body, "position:z", target.y, total * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Sube, cae y rebota cada vez menos (como un dado de verdad).
	var hop: Tween = create_tween()
	_tweens.append(hop)
	var bounces: Array = [[HOP_HEIGHT, 0.36, 0.21], [0.75, 0.14, 0.11], [0.28, 0.08, 0.05], [0.09, 0.03, 0.02]]
	for bounce in bounces:
		var height: float = float((bounce as Array)[0])
		var up_time: float = float((bounce as Array)[1]) * total
		var down_time: float = float((bounce as Array)[2]) * total
		hop.tween_property(_body, "position:y", _rest_y + height, up_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hop.tween_property(_body, "position:y", _rest_y, down_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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


## Altura de la cara superior del dado en reposo, útil para colocar textos sobre él.
func top_position() -> Vector3:
	return global_position + Vector3(_body.position.x, SIZE + 0.2, _body.position.z)


func _on_roll_finished(value: int, final_rotation: Vector3) -> void:
	_body.rotation = final_rotation
	_body.position.y = _rest_y
	is_rolling = false
	set_process(false)
	_update_shadow()
	roll_finished.emit(value)


func _clear_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


## Sombra redonda bajo el dado: se agranda y se aclara cuando el dado está en el aire.
func _update_shadow() -> void:
	if _shadow == null:
		return
	var lift: float = clampf((_body.position.y - _rest_y) / HOP_HEIGHT, 0.0, 1.0)
	var scale_value: float = lerpf(1.0, 1.7, lift)
	_shadow.position = Vector3(_body.position.x, 0.015, _body.position.z)
	_shadow.scale = Vector3(scale_value, 1.0, scale_value)
	var material := _shadow.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = lerpf(0.55, 0.18, lift)


func _build_shadow() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.albedo_color = Color(0.05, 0.03, 0.01, 0.55)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE * 1.5, SIZE * 1.5)
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	_shadow.mesh = plane
	_shadow.material_override = material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	_update_shadow()


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
