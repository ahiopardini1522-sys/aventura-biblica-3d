class_name FxKit
extends RefCounted
## Efectos de ambiente baratos para los escenarios: partículas flotantes (polen, polvo,
## luciérnagas, niebla de cascada), nubes que se desplazan, aves que vuelan en círculo,
## cielo estrellado y haces de luz. Las animaciones usan Tween, así que solo se crean cuando
## el escenario ya está dentro del árbol de la escena y se detienen con la pausa.

static var _cloud_material: StandardMaterial3D


## Partículas que flotan dentro de una caja. "rise" es la aceleración hacia arriba (negativa
## cae, positiva sube). Se desvanecen al nacer y al morir.
static func floaters(parent: Node3D, node_name: String, center: Vector3, extents: Vector3,
		amount: int, size: float, color: Color, rise: float = 0.04, lifetime: float = 8.0,
		additive: bool = false) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, rise, 0.0)
	particles.initial_velocity_min = 0.05
	particles.initial_velocity_max = 0.3
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	particles.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.25, Color(1.0, 1.0, 1.0, 1.0))
	ramp.add_point(0.75, Color(1.0, 1.0, 1.0, 1.0))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	particles.mesh = quad
	particles.material_override = TextureKit.particle_material(additive)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = center
	parent.add_child(particles)
	return particles


## Nubes blandas que se desplazan despacio. Cada una es una sola malla.
static func clouds(parent: Node3D, rng: RandomNumberGenerator, count: int, y_min: float,
		y_max: float, radius: float, tint: Color = Color(1.0, 1.0, 1.0, 0.9)) -> void:
	if _cloud_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cloud_material = m
	for i in count:
		var kit := MeshKit.new()
		var puffs: int = rng.randi_range(4, 7)
		var under: Color = Color(tint.r * 0.84, tint.g * 0.88, tint.b * 0.97, tint.a)
		for k in puffs:
			var r: float = rng.randf_range(3.5, 7.0)
			kit.sphere(Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-0.8, 1.2), rng.randf_range(-3.0, 3.0)),
					Vector3(r * 1.4, r * 0.5, r * 0.9), tint, 8, 4, 0.08, rng, PI, under)
		var cloud: MeshInstance3D = kit.instance(_cloud_material, "Cloud")
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(radius * 0.4, radius)
		cloud.position = Vector3(cos(angle) * distance, rng.randf_range(y_min, y_max), sin(angle) * distance)
		cloud.rotation.y = rng.randf_range(0.0, TAU)
		parent.add_child(cloud)
		if parent.is_inside_tree():
			var drift: float = rng.randf_range(14.0, 26.0)
			var seconds: float = rng.randf_range(50.0, 90.0)
			var tween: Tween = cloud.create_tween()
			tween.set_loops()
			tween.tween_property(cloud, "position:x", cloud.position.x + drift, seconds) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(cloud, "position:x", cloud.position.x, seconds) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Aves que vuelan en círculo alrededor de "center" aleteando.
static func birds(parent: Node3D, rng: RandomNumberGenerator, count: int, center: Vector3,
		radius: float, height: float, color: Color) -> void:
	var material: StandardMaterial3D = TextureKit.plain(0.8)
	for i in count:
		var pivot := Node3D.new()
		pivot.name = "BirdOrbit"
		pivot.position = Vector3(center.x, height + rng.randf_range(-2.0, 3.0), center.z)
		pivot.rotation.y = rng.randf_range(0.0, TAU)
		parent.add_child(pivot)

		var bird := Node3D.new()
		bird.name = "Bird"
		bird.position = Vector3(radius * rng.randf_range(0.7, 1.2), 0.0, 0.0)
		pivot.add_child(bird)

		var body := MeshKit.new()
		body.sphere(Vector3.ZERO, Vector3(0.12, 0.1, 0.34), color, 6, 4)
		body.sphere(Vector3(0.0, 0.04, -0.32), Vector3(0.07, 0.07, 0.09), color, 6, 3)
		body.box(Vector3(0.0, 0.0, 0.4), Vector3(0.12, 0.02, 0.2), color.darkened(0.12))
		bird.add_child(body.instance(material, "Body"))

		var wing_tweens: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var sign_value: float = side
			var wing_pivot := Node3D.new()
			wing_pivot.name = "Wing"
			wing_pivot.position = Vector3(sign_value * 0.08, 0.04, 0.0)
			bird.add_child(wing_pivot)
			var wing := MeshKit.new()
			wing.box(Vector3(sign_value * 0.3, 0.0, 0.0), Vector3(0.6, 0.02, 0.3), color.lightened(0.05))
			wing_pivot.add_child(wing.instance(material, "WingMesh"))
			wing_tweens.append(wing_pivot)

		if parent.is_inside_tree():
			var orbit: Tween = pivot.create_tween()
			orbit.set_loops()
			orbit.tween_property(pivot, "rotation:y", TAU, rng.randf_range(26.0, 38.0)).as_relative()
			for wing_node in wing_tweens:
				var sign_flap: float = 1.0 if wing_node.position.x > 0.0 else -1.0
				wing_node.rotation.z = sign_flap * 0.5
				var flap: Tween = wing_node.create_tween()
				flap.set_loops()
				flap.tween_property(wing_node, "rotation:z", sign_flap * -0.4, 0.32)
				flap.tween_property(wing_node, "rotation:z", sign_flap * 0.5, 0.32)


## Cielo estrellado: puntitos brillantes sobre una media esfera enorme (sin niebla).
static func star_dome(parent: Node3D, rng: RandomNumberGenerator, count: int, radius: float = 230.0) -> MeshInstance3D:
	var kit := MeshKit.new()
	for i in count:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.06, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var up: Vector3 = Vector3.UP
		if absf(dir.y) > 0.98:
			up = Vector3.RIGHT
		var half: float = rng.randf_range(0.5, 1.4) * radius / 230.0
		var bright: float = rng.randf_range(0.55, 1.0)
		var color := Color(bright, bright, minf(1.0, bright * 1.05), 1.0)
		kit.push_xf(Transform3D(Basis.looking_at(-dir, up), dir * radius))
		var a := Vector3(0.0, half, 0.0)
		var b := Vector3(half, 0.0, 0.0)
		var c := Vector3(0.0, -half, 0.0)
		var d := Vector3(-half, 0.0, 0.0)
		kit.quad(a, b, c, d, color, Vector3.BACK)
		kit.quad(a, b, c, d, color, Vector3.FORWARD)
		kit.pop()
	var dome: MeshInstance3D = kit.instance(TextureKit.glow_vertex(true), "Stars")
	parent.add_child(dome)
	return dome


## Haz de luz vertical que se desvanece hacia arriba (luz celestial, estrella de Belén).
static func beam(parent: Node3D, base: Vector3, height: float, radius_bottom: float,
		radius_top: float, color: Color, sections: int = 6) -> MeshInstance3D:
	var kit := MeshKit.new()
	var count: int = maxi(2, sections)
	for i in count:
		var t0: float = float(i) / float(count)
		var t1: float = float(i + 1) / float(count)
		var fade: float = pow(1.0 - (t0 + t1) * 0.5, 1.4)
		var tint := Color(color.r, color.g, color.b, color.a * fade)
		kit.cylinder(base + Vector3(0.0, height * t0, 0.0), lerpf(radius_bottom, radius_top, t0),
				lerpf(radius_bottom, radius_top, t1), height / float(count), 10, tint, false, false)
	var node: MeshInstance3D = kit.instance(TextureKit.glow_vertex(true), "Beam")
	parent.add_child(node)
	return node


## Bola de luz (llama, fruto brillante, lámpara).
static func glow_ball(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var kit := MeshKit.new()
	kit.sphere(pos, Vector3(radius, radius, radius), color, 8, 5)
	var node: MeshInstance3D = kit.instance(TextureKit.glow_vertex(true), "Glow")
	parent.add_child(node)
	return node
