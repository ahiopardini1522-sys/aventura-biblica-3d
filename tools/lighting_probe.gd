extends SceneTree
## Sonda de iluminación: mide cuánta luz recibe una superficie gris plana con el
## renderizador activo (en CI, OpenGL por software; en el teléfono, OpenGL ES 3).
## Sirve para elegir las energías de luz de cada escena sin adivinar:
##   LIGHT_E = luz_ambiente * E_ambiente + luz_sol * E_sol * sen(elevación)
## La ejecuta GitHub Actions junto a las capturas:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/lighting_probe.gd

const ALBEDO_SRGB := 0.5
const TIME_LIMIT := 120.0

var _finished: bool = false
var _linear_albedo: float = 0.0


func _initialize() -> void:
	create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run()


func _on_time_limit() -> void:
	if _finished:
		return
	_finished = true
	print("SONDA: tiempo agotado")
	quit(2)


func _run() -> void:
	await process_frame
	_linear_albedo = Color(ALBEDO_SRGB, ALBEDO_SRGB, ALBEDO_SRGB).srgb_to_linear().r
	print("SONDA: albedo gris sRGB %.2f = lineal %.4f" % [ALBEDO_SRGB, _linear_albedo])

	# Tono lineal: el valor leído es directamente albedo * luz (hasta 1.0).
	var linear: int = Environment.TONE_MAPPER_LINEAR
	var filmic: int = Environment.TONE_MAPPER_FILMIC
	await _measure("solo ambiente, energía 1.0 (lineal)", 1.0, 0.0, 90.0, linear)
	await _measure("solo ambiente, energía 0.5 (lineal)", 0.5, 0.0, 90.0, linear)
	await _measure("solo sol cenital, energía 1.0 (lineal)", 0.0, 1.0, 90.0, linear)
	await _measure("solo sol cenital, energía 0.5 (lineal)", 0.0, 0.5, 90.0, linear)
	await _measure("solo sol a 40 grados, energía 1.0 (lineal)", 0.0, 1.0, 40.0, linear)
	await _measure("ambiente 0.5 + sol cenital 0.5 (lineal)", 0.5, 0.5, 90.0, linear)
	await _measure("ambiente 0.5 + sol cenital 0.5 (filmic)", 0.5, 0.5, 90.0, filmic)
	await _measure("solo ambiente, energía 1.0 (filmic)", 1.0, 0.0, 90.0, filmic)

	_finished = true
	print("SONDA: lista")
	quit(0)


func _measure(label: String, ambient_energy: float, sun_energy: float, elevation: float,
		tonemap: int) -> void:
	var holder: Node3D = _build_scene(ambient_energy, sun_energy, elevation, tonemap)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var pixel: Color = image.get_pixel(floori(image.get_width() * 0.5), floori(image.get_height() * 0.5))
	var linear_pixel: Color = pixel.srgb_to_linear()
	var gain: float = linear_pixel.r / _linear_albedo
	print("SONDA: %-46s pixel sRGB=%.3f lineal=%.3f -> ganancia=%.3f" % [label, pixel.r, linear_pixel.r, gain])
	root.remove_child(holder)
	holder.queue_free()
	await process_frame


func _build_scene(ambient_energy: float, sun_energy: float, elevation: float, tonemap: int) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = tonemap as Environment.ToneMapper
	var world := WorldEnvironment.new()
	world.environment = env
	holder.add_child(world)

	if sun_energy > 0.0:
		var sun := DirectionalLight3D.new()
		sun.light_energy = sun_energy
		sun.shadow_enabled = false
		holder.add_child(sun)
		sun.rotation_degrees = Vector3(-elevation, 0.0, 0.0)

	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(ALBEDO_SRGB, ALBEDO_SRGB, ALBEDO_SRGB)
	material.roughness = 1.0
	var quad := MeshInstance3D.new()
	quad.mesh = plane
	quad.material_override = material
	holder.add_child(quad)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	holder.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 5.0, 0.0), Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	camera.current = true
	return holder
