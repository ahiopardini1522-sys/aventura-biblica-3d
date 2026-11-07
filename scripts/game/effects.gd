class_name Effects
extends RefCounted
## Efectos visuales 3D de corta vida: chispas, estrellas, aros de luz, columnas de luz,
## textos flotantes, polvo y confeti. Cada uno se crea como hijo del nodo que se le pasa
## (conviene un Node3D sin transformación, para que las posiciones sean las del mundo)
## y se borra solo al terminar. Solo usan primitivas y partículas de CPU, que funcionan
## igual de bien en el renderizador Compatibility del móvil.

const GOLD := Color(1.0, 0.84, 0.40)
const GREEN := Color(0.50, 0.95, 0.55)
const RED := Color(1.0, 0.38, 0.30)
const BLUE := Color(0.55, 0.80, 1.0)
const WHITE := Color(1.0, 0.98, 0.92)
const CONFETTI_COLORS := [
	Color(1.0, 0.82, 0.30),
	Color(0.95, 0.38, 0.35),
	Color(0.40, 0.78, 0.95),
	Color(0.55, 0.88, 0.45),
	Color(0.80, 0.50, 0.95),
	Color(1.0, 0.62, 0.25),
]


## Estallido de chispas redondas que salen en todas direcciones.
static func sparkle_burst(parent: Node, at: Vector3, color: Color, count: int = 24, speed: float = 3.2,
		lifetime: float = 0.9, size: float = 0.13) -> CPUParticles3D:
	if not _usable(parent):
		return null
	var particles: CPUParticles3D = _new_particles(count, lifetime)
	particles.position = at
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0.0, -5.0, 0.0)
	particles.damping_min = 0.8
	particles.damping_max = 2.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	particles.color = color
	particles.color_ramp = _fade_ramp()
	var spark := SphereMesh.new()
	spark.radius = size
	spark.height = size * 2.0
	spark.radial_segments = 6
	spark.rings = 3
	spark.material = _particle_material(false)
	particles.mesh = spark
	parent.add_child(particles)
	_finish_after(particles, lifetime + 0.4)
	return particles


## Lluvia de estrellas doradas que suben y se apagan (acierto, recompensa, victoria).
static func star_shower(parent: Node, at: Vector3, color: Color = GOLD, count: int = 16,
		lifetime: float = 1.3, size: float = 0.22) -> CPUParticles3D:
	if not _usable(parent):
		return null
	var particles: CPUParticles3D = _new_particles(count, lifetime)
	particles.position = at
	particles.direction = Vector3.UP
	particles.spread = 38.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.2
	particles.gravity = Vector3(0.0, -3.2, 0.0)
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	particles.angular_velocity_min = -220.0
	particles.angular_velocity_max = 220.0
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.25
	particles.color = color
	particles.color_ramp = _fade_ramp()
	particles.mesh = star_mesh(size)
	parent.add_child(particles)
	_finish_after(particles, lifetime + 0.4)
	return particles


## Nubecita de polvo al aterrizar la ficha o al caer por una serpiente.
static func dust_puff(parent: Node, at: Vector3, color: Color = Color(0.92, 0.84, 0.70),
		count: int = 10, lifetime: float = 0.7) -> CPUParticles3D:
	if not _usable(parent):
		return null
	var particles: CPUParticles3D = _new_particles(count, lifetime)
	particles.position = at + Vector3(0.0, 0.05, 0.0)
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.3
	particles.gravity = Vector3(0.0, 0.2, 0.0)
	particles.damping_min = 1.5
	particles.damping_max = 3.0
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.4
	particles.color = Color(color, 0.55)
	particles.color_ramp = _fade_ramp()
	var puff := SphereMesh.new()
	puff.radius = 0.1
	puff.height = 0.2
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = _particle_material(false)
	particles.mesh = puff
	parent.add_child(particles)
	_finish_after(particles, lifetime + 0.4)
	return particles


## Aro de luz que crece desde un punto del suelo y se desvanece.
static func ring_pulse(parent: Node, at: Vector3, color: Color, radius: float = 1.3,
		duration: float = 0.7) -> MeshInstance3D:
	if not _usable(parent):
		return null
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.84
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 6
	var material: StandardMaterial3D = MeshFactory.glow_material(Color(color, 0.9))
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at
	ring.scale = Vector3(0.1, 0.03, 0.1)
	parent.add_child(ring)
	var length: float = maxf(duration, 0.05)
	var tween: Tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, radius * 0.25, radius), length) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, length) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	return ring


## Columna de luz que se enciende y se apaga (llegada a lo alto de una escalera, a la meta...).
static func light_pillar(parent: Node, at: Vector3, color: Color, height: float = 3.2,
		duration: float = 0.9) -> MeshInstance3D:
	if not _usable(parent):
		return null
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.42
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material: StandardMaterial3D = MeshFactory.glow_material(Color(color, 0.0))
	var pillar := MeshInstance3D.new()
	pillar.mesh = mesh
	pillar.material_override = material
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = at + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(pillar)
	var length: float = maxf(duration, 0.1)
	var tween: Tween = pillar.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.55, length * 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, length * 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(pillar.queue_free)
	return pillar


## Texto que aparece con un saltito, sube y se desvanece ("+2", "¡Escalera!", "-2"...).
static func floating_text(parent: Node, at: Vector3, text: String, color: Color,
		scale_factor: float = 1.0, rise: float = 1.3, duration: float = 1.5) -> Label3D:
	if not _usable(parent):
		return null
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0072 * scale_factor
	label.outline_size = 26
	label.outline_modulate = Color(0.10, 0.05, 0.02, 0.95)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.no_depth_test = true
	label.render_priority = 10
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	label.scale = Vector3.ONE * 0.2
	parent.add_child(label)
	var length: float = maxf(duration, 0.2)
	var tween: Tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", at.y + rise, length) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, length * 0.35).set_delay(length * 0.65)
	tween.tween_property(label, "outline_modulate:a", 0.0, length * 0.35).set_delay(length * 0.65)
	tween.chain().tween_callback(label.queue_free)
	return label


## Confeti que cae durante "lifetime" segundos desde una caja sobre "at" (pantalla de victoria).
## Con "loop" true sigue cayendo hasta que se borre el nodo devuelto.
static func confetti(parent: Node, at: Vector3, extents: Vector3 = Vector3(5.0, 0.2, 3.0),
		count: int = 120, lifetime: float = 3.4, loop: bool = true) -> CPUParticles3D:
	if not _usable(parent):
		return null
	var particles := CPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.one_shot = not loop
	particles.explosiveness = 0.0 if loop else 0.6
	particles.preprocess = lifetime * 0.5 if loop else 0.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = at
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3.DOWN
	particles.spread = 18.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.4
	particles.gravity = Vector3(0.0, -1.1, 0.0)
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	particles.angular_velocity_min = -280.0
	particles.angular_velocity_max = 280.0
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.4
	var palette := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in CONFETTI_COLORS.size():
		offsets.append(float(i) / float(CONFETTI_COLORS.size() - 1))
		colors.append(CONFETTI_COLORS[i])
	palette.offsets = offsets
	palette.colors = colors
	particles.color_initial_ramp = palette
	var piece := QuadMesh.new()
	piece.size = Vector2(0.13, 0.2)
	piece.material = _particle_material(true)
	particles.mesh = piece
	parent.add_child(particles)
	if not loop:
		_finish_after(particles, lifetime + 0.6)
	particles.emitting = true
	return particles


## Estrella plana de cinco puntas (mira hacia +Z); las partículas la giran hacia la cámara.
static func star_mesh(radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[Vector3] = []
	for i in 10:
		var angle: float = PI * 0.5 + float(i) * PI / 5.0
		var reach: float = radius if i % 2 == 0 else radius * 0.45
		tips.append(Vector3(cos(angle) * reach, sin(angle) * reach, 0.0))
	for i in 10:
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(tips[i])
		surface.add_vertex(tips[(i + 1) % 10])
	var mesh: ArrayMesh = surface.commit()
	mesh.surface_set_material(0, _particle_material(false, true))
	return mesh


# ---------------------------------------------------------------- Ayudas

static func _usable(parent: Node) -> bool:
	return parent != null and parent.is_inside_tree()


static func _new_particles(count: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = maxi(1, count)
	particles.lifetime = maxf(lifetime, 0.1)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	return particles


## Material de las partículas: toma el color de cada partícula (vertex color). "solid" es
## para piezas opacas como el confeti; si no, brilla sumando luz. "face_camera" las gira de frente.
static func _particle_material(solid: bool, face_camera: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D
	if solid:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color.WHITE
	else:
		material = MeshFactory.glow_material(Color(1.0, 1.0, 1.0, 0.95))
	material.vertex_color_use_as_albedo = true
	if solid or face_camera:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.billboard_keep_scale = true
		material.particles_anim_h_frames = 1
		material.particles_anim_v_frames = 1
		material.particles_anim_loop = false
	return material


## Degradado que mantiene la partícula opaca al principio y la apaga al final.
static func _fade_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	return ramp


static func _finish_after(node: Node, seconds: float) -> void:
	var tween: Tween = node.create_tween()
	tween.tween_interval(maxf(seconds, 0.05))
	tween.tween_callback(node.queue_free)
