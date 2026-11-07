class_name MenuBackdrop
extends Node3D
## Fondo 3D de todas las pantallas del menú: un valle del desierto al amanecer,
## con río, palmeras, montañas y una escalera de luz que sube al cielo
## (el sueño de Jacob en Betel). La cámara se mueve despacio sobre el paisaje.

const LADDER_BASE := Vector3(11.0, 0.0, -36.0)
const LADDER_TOP_OFFSET := Vector3(-8.0, 74.0, -18.0)
const LADDER_SEGMENTS := 10
const LADDER_RAIL_GAP := 3.2

@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _sun: DirectionalLight3D = %Sun
@onready var _scenery: Node3D = %Scenery
@onready var _camera: Camera3D = %Camera3D

var _time: float = 0.0
var _clouds: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2024
	_time = randf() * 20.0
	_world_env.environment = EnvFactory.create(
		Color(0.22, 0.42, 0.78), Color(0.99, 0.80, 0.55), Color(0.55, 0.42, 0.30),
		Color(1.0, 0.88, 0.72), Color(0.97, 0.78, 0.56), 0.0075, 0.9)
	# El sol queda bajo, a la izquierda y al frente de la cámara.
	var sun_in_sky: Vector3 = Vector3(-0.55, 0.20, -0.81).normalized()
	_sun.transform = Transform3D(Basis.looking_at(-sun_in_sky, Vector3.UP), Vector3.ZERO)
	_build_terrain()
	_build_props()
	_build_ladder()
	_build_clouds()
	_update_camera()


func _process(delta: float) -> void:
	_time += delta
	_update_camera()
	for i in _clouds.size():
		var cloud: Node3D = _clouds[i]
		cloud.position.x += delta * (0.5 + 0.07 * float(i))
		if cloud.position.x > 85.0:
			cloud.position.x = -85.0


func _update_camera() -> void:
	var t: float = _time
	var pos := Vector3(-3.0 + sin(t * 0.11) * 5.0, 0.0, 24.0 + cos(t * 0.07) * 2.5)
	pos.y = maxf(LandscapeBuilder.height_at(pos.x, pos.z) + 4.5, 6.5) + sin(t * 0.17) * 0.5
	var target := Vector3(5.0 + sin(t * 0.09) * 2.0, 13.0 + sin(t * 0.13) * 1.2, -26.0)
	_camera.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


func _build_terrain() -> void:
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = LandscapeBuilder.terrain_mesh()
	terrain.material_override = MeshFactory.vertex_color_material(0.95)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scenery.add_child(terrain)

	var water := MeshInstance3D.new()
	water.name = "River"
	water.mesh = LandscapeBuilder.river_mesh()
	var water_mat: StandardMaterial3D = MeshFactory.material(Color(0.20, 0.50, 0.72, 0.84), 0.1, 0.2)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.12, 0.32, 0.48)
	water_mat.emission_energy_multiplier = 0.5
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scenery.add_child(water)


func _build_props() -> void:
	# Palmeras en las orillas del río.
	for i in 16:
		var z: float = _rng.randf_range(-44.0, 34.0)
		var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
		var x: float = LandscapeBuilder.river_center_x(z) + side * _rng.randf_range(8.0, 15.0)
		if absf(x) > 52.0:
			continue
		var palm: Node3D = PropFactory.palm(_rng, _rng.randf_range(3.2, 4.4))
		palm.position = Vector3(x, LandscapeBuilder.height_at(x, z) - 0.1, z)
		palm.rotation.y = _rng.randf_range(0.0, TAU)
		palm.scale = Vector3.ONE * _rng.randf_range(1.0, 1.5)
		_scenery.add_child(palm)

	# Rocas dispersas lejos del agua.
	for i in 26:
		var x: float = _rng.randf_range(-52.0, 52.0)
		var z: float = _rng.randf_range(-52.0, 30.0)
		if absf(x - LandscapeBuilder.river_center_x(z)) < 9.0:
			continue
		var h: float = LandscapeBuilder.height_at(x, z)
		if h > 12.0:
			continue
		var rock: MeshInstance3D = PropFactory.rock(_rng)
		rock.position = Vector3(x, h + 0.1, z)
		rock.scale *= _rng.randf_range(0.8, 2.4)
		_scenery.add_child(rock)


## La escalera de Jacob: dos rieles y peldaños de luz que se desvanecen hacia el cielo.
func _build_ladder() -> void:
	var base: Vector3 = LADDER_BASE
	base.y = LandscapeBuilder.height_at(base.x, base.z) - 0.5
	var axis: Vector3 = LADDER_TOP_OFFSET.normalized()
	var length: float = LADDER_TOP_OFFSET.length()

	var ladder := Node3D.new()
	ladder.name = "JacobsLadder"
	ladder.transform = Transform3D(Basis.looking_at(axis, Vector3.UP), base)
	_scenery.add_child(ladder)

	var seg_len: float = length / float(LADDER_SEGMENTS)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.22, 0.22, seg_len)
	var rung_mesh := BoxMesh.new()
	rung_mesh.size = Vector3(LADDER_RAIL_GAP + 0.22, 0.14, 0.14)
	var rungs_per_segment: int = 5

	for s in LADDER_SEGMENTS:
		var fade: float = 1.0 - float(s) / float(LADDER_SEGMENTS)
		var material: StandardMaterial3D = MeshFactory.glow_material(
				Color(1.0, 0.86, 0.5, 0.08 + 0.85 * pow(fade, 1.4)))
		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			rail.mesh = rail_mesh
			rail.material_override = material
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rail.position = Vector3(float(side) * LADDER_RAIL_GAP * 0.5, 0.0, -(float(s) + 0.5) * seg_len)
			ladder.add_child(rail)
		for r in rungs_per_segment:
			var rung := MeshInstance3D.new()
			rung.mesh = rung_mesh
			rung.material_override = material
			rung.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rung.position = Vector3(0.0, 0.0, -(float(s) + (float(r) + 0.5) / float(rungs_per_segment)) * seg_len)
			ladder.add_child(rung)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 11.0
	halo_mesh.height = 22.0
	halo_mesh.radial_segments = 16
	halo_mesh.rings = 8
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	halo.material_override = MeshFactory.glow_material(Color(1.0, 0.86, 0.55, 0.22))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0.0, 0.0, -length)
	ladder.add_child(halo)

	# Destellos que suben y bajan por la escalera.
	ladder.add_child(_make_sparkles(Vector3(0.0, 0.0, -1.0), Vector3.ZERO, length))
	ladder.add_child(_make_sparkles(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -length), length))


func _make_sparkles(direction: Vector3, origin: Vector3, length: float) -> CPUParticles3D:
	var lifetime: float = 16.0
	var particles := CPUParticles3D.new()
	particles.position = origin
	particles.amount = 28
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.local_coords = true
	particles.direction = direction
	particles.spread = 3.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = length / lifetime * 0.9
	particles.initial_velocity_max = length / lifetime * 1.1
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(LADDER_RAIL_GAP * 0.5, 0.2, 0.2)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark := SphereMesh.new()
	spark.radius = 0.22
	spark.height = 0.44
	spark.radial_segments = 8
	spark.rings = 4
	spark.material = MeshFactory.glow_material(Color(1.0, 0.95, 0.75, 0.9))
	particles.mesh = spark
	return particles


func _build_clouds() -> void:
	for i in 7:
		var cloud: MeshInstance3D = PropFactory.cloud(_rng)
		cloud.position = Vector3(_rng.randf_range(-70.0, 70.0), _rng.randf_range(34.0, 52.0),
				_rng.randf_range(-75.0, -35.0))
		_scenery.add_child(cloud)
		_clouds.append(cloud)
