class_name WorldMapBuilder
extends Node3D
## El mapa mundial 3D "MUNDO BÍBLICO": un continente rodeado de mar, con relieve y montañas, siete
## plataformas-región (cada una con su icono 3D, su decorado y su nombre) y caminos que las unen
## en el orden en que se abren. Cada región muestra su estado con figuras propias:
##   bloqueada   candado dorado flotando, icono y terreno apagados, camino gris
##   abierta     aro de luz que late y camino con destellos dorados
##   completada  aro verde y estrella dorada
## La región elegida lleva un aro blanco y "salta"; la próxima que hay que jugar lleva una flecha.
##
## Todo se construye con mallas combinadas (ver MeshKit): unos 80 objetos y unos 35 mil triángulos.
## build() hay que llamarlo con el nodo ya dentro del árbol de la escena (las animaciones usan Tween).

const WORLD_SCALE := 1.4
const HALF := 144.0
## Celdas del terreno por lado (3 unidades cada una): así ningún triángulo del terreno que toque
## una plataforma llega a una zona que no esté plana.
const CELLS := 96
const SEA_Y := -1.7
const SEA_FLOOR := -4.5
## El suelo plano está en y = 0 y las plataformas sobresalen un poco (PAD_Y).
const GROUND_Y := 0.0
const PAD_Y := 0.45
const PAD_RADIUS := 8.5
const FLAT_RADIUS := 11.5
const FLAT_FALLOFF := 9.0
const ROAD_HALF_WIDTH := 1.4
const ROAD_FLAT_WIDTH := 5.5
const ROAD_FLAT_FALLOFF := 5.0
const ROAD_Y := 0.16
const BIOME_RADIUS := 24.0
const LABEL_LIFT := 6.4
const ARROW_LIFT := 9.6
const LOCK_SCALE := 1.8

# Luz del mapa: las mismas energías de la escena del tablero (ver MapEnvironment).
const SUN_ENERGY := 0.26
const AMBIENT_ENERGY := 0.28
const FOG_DENSITY := 0.0022

## Cordilleras y cerros: (x, z, radio, altura). Todos dentro del continente y lejos de las plataformas.
const RANGES: Array = [
	Vector4(-30.0, -44.0, 18.0, 16.0),  # Ararat, al norte del Arca
	Vector4(-4.0, -40.0, 16.0, 8.0),
	Vector4(60.0, -38.0, 20.0, 13.0),  # montes del Líbano
	Vector4(14.0, 36.0, 22.0, 14.0),  # sierra al sur del Sinaí
	Vector4(38.0, 20.0, 14.0, 9.0),
	Vector4(-96.0, -2.0, 16.0, 12.0),  # colinas al oeste del Edén
	Vector4(92.0, 18.0, 14.0, 8.0),
	Vector4(-64.0, 30.0, 14.0, 8.0),
]

const COLOR_LOCKED := Color(0.46, 0.48, 0.56)
const COLOR_NIGHT := Color(0.58, 0.66, 1.0)
const GOLD := Color(1.0, 0.86, 0.36)

static var _region_ids: Array[String] = []
static var _region_spots: Dictionary = {}
static var _region_colors: Dictionary = {}
static var _roads: Array = []
static var _layout_ready: bool = false
static var _terrain_mesh: ArrayMesh


## Todo lo que el nodo de una región necesita para cambiar de estado y animarse.
class RegionNode:
	var id: String = ""
	var root: Node3D
	var icon: Node3D
	var icon_mesh: MeshInstance3D
	var icon_glow: MeshInstance3D
	var pad: MeshInstance3D
	var decor: MeshInstance3D
	var decor_glow: MeshInstance3D
	var lock: MeshInstance3D
	var halo: MeshInstance3D
	var done_ring: MeshInstance3D
	var star: MeshInstance3D
	var selector: MeshInstance3D
	var label: Label3D
	var status: String = "locked"
	var night: bool = false
	var top: float = 8.0
	var phase: float = 0.0
	var pop_tweens: Array = []


var selected_id: String = ""
var next_id: String = ""

var _quality: int = 1
var _density: float = 1.0
var _time: float = 0.0
var _regions: Dictionary = {}
var _road_nodes: Array = []
var _regions_root: Node3D
var _roads_root: Node3D
var _arrow: MeshInstance3D
var _model_day: StandardMaterial3D
var _model_night: StandardMaterial3D
var _model_locked: StandardMaterial3D
var _pad_day: StandardMaterial3D
var _pad_locked: StandardMaterial3D
var _road_open: StandardMaterial3D
var _road_closed: StandardMaterial3D


# ---------------------------------------------------------------- Disposición (sin nodos)

## Calcula dónde está cada región y por dónde pasa cada camino. Se vuelve a calcular cada vez que se
## llama (por si cambió el catálogo); las funciones de altura y color la usan.
static func prepare_layout() -> void:
	_region_ids.clear()
	_region_spots.clear()
	_region_colors.clear()
	_roads.clear()
	for entry in MapCatalog.all_maps():
		var map_data: Dictionary = entry
		var id: String = str(map_data["id"])
		_region_ids.append(id)
		_region_spots[id] = MapCatalog.world_position(id) * WORLD_SCALE
		var theme_data: Dictionary = map_data["theme"]
		var ground := Color(0.40, 0.60, 0.30)
		var raw: Variant = theme_data.get("ground", ground)
		if raw is Color:
			ground = raw
		_region_colors[id] = ground
	var bend: float = 7.0
	for id in _region_ids:
		var needs: String = MapCatalog.requirement_of(id)
		if needs.is_empty() or not _region_spots.has(needs):
			continue
		var from_spot: Vector2 = _region_spots[needs]
		var to_spot: Vector2 = _region_spots[id]
		var path: PackedVector2Array = road_path(from_spot, to_spot, bend)
		bend = -bend
		_roads.append({
			"from": needs,
			"to": id,
			"path": path,
			"bounds": _path_bounds(path, ROAD_FLAT_WIDTH + ROAD_FLAT_FALLOFF + 1.0),
		})
	_layout_ready = true


## Posición (x, z) de la región en el mundo 3D.
static func region_spot(id: String) -> Vector2:
	if not _layout_ready:
		prepare_layout()
	if _region_spots.has(id):
		return _region_spots[id]
	return Vector2.ZERO


## Cantidad de caminos (uno por cada región que pide completar otra antes).
static func road_count() -> int:
	if not _layout_ready:
		prepare_layout()
	return _roads.size()


## Puntos (x, z) del camino número "index" y los ids de las dos regiones que une.
static func road_points(index: int) -> PackedVector2Array:
	if not _layout_ready:
		prepare_layout()
	if index < 0 or index >= _roads.size():
		return PackedVector2Array()
	var info: Dictionary = _roads[index]
	return info["path"]


static func road_from(index: int) -> String:
	if not _layout_ready:
		prepare_layout()
	if index < 0 or index >= _roads.size():
		return ""
	var info: Dictionary = _roads[index]
	return str(info["from"])


static func road_to(index: int) -> String:
	if not _layout_ready:
		prepare_layout()
	if index < 0 or index >= _roads.size():
		return ""
	var info: Dictionary = _roads[index]
	return str(info["to"])


## Camino curvo de una plataforma a la otra: de borde a borde, con una curva suave.
static func road_path(from_spot: Vector2, to_spot: Vector2, bend: float, steps: int = 14) -> PackedVector2Array:
	var delta: Vector2 = to_spot - from_spot
	var length: float = delta.length()
	var path := PackedVector2Array()
	if length < 0.001:
		path.append(from_spot)
		path.append(to_spot)
		return path
	var direction: Vector2 = delta / length
	var start: Vector2 = from_spot + direction * (PAD_RADIUS - 0.4)
	var finish: Vector2 = to_spot - direction * (PAD_RADIUS - 0.4)
	var side := Vector2(-direction.y, direction.x)
	var control: Vector2 = (start + finish) * 0.5 + side * bend
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		path.append(start.lerp(control, t).lerp(control.lerp(finish, t), t))
	return path


static func _path_bounds(path: PackedVector2Array, margin: float) -> Rect2:
	var low: Vector2 = path[0]
	var high: Vector2 = path[0]
	for point in path:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	return Rect2(low - Vector2(margin, margin), (high - low) + Vector2(margin, margin) * 2.0)


static func _distance_to_path(point: Vector2, path: PackedVector2Array) -> float:
	var best: float = 1000000.0
	for i in path.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


## 1 sobre el continente y 0 en el mar (con una costa irregular).
static func land_mask(x: float, z: float) -> float:
	var nx: float = x / 122.0
	var nz: float = z / 60.0
	var d: float = sqrt(nx * nx + nz * nz)
	d += 0.05 * sin(x * 0.11 + 1.3) + 0.05 * sin(z * 0.19 + x * 0.04) + 0.03 * sin(x * 0.29 - z * 0.23)
	return 1.0 - smoothstep(0.82, 1.0, d)


static func hills(x: float, z: float) -> float:
	return 1.5 * sin(x * 0.07 + 0.6) * cos(z * 0.09 - 0.4) + 1.0 * sin(x * 0.16 - z * 0.12 + 2.0) \
			+ 0.45 * sin(x * 0.33 + z * 0.29)


static func _bump(x: float, z: float, center: Vector4) -> float:
	var dx: float = x - center.x
	var dz: float = z - center.y
	var ratio: float = (dx * dx + dz * dz) / (center.z * center.z)
	if ratio >= 1.0:
		return 0.0
	var k: float = 1.0 - ratio
	return center.w * k * k


## Altura del terreno en (x, z): mar y costa, colinas, cordilleras, y plano bajo las plataformas
## y los caminos para que todo se apoye bien.
static func height_at(x: float, z: float) -> float:
	if not _layout_ready:
		prepare_layout()
	var land: float = land_mask(x, z)
	var h: float = lerpf(SEA_FLOOR, 0.0, smoothstep(0.0, 0.55, land))
	var relief: float = hills(x, z)
	for entry in RANGES:
		var center: Vector4 = entry
		relief += _bump(x, z, center)
	h += relief * smoothstep(0.35, 0.9, land)
	var here := Vector2(x, z)
	var flat: float = 0.0
	for id in _region_ids:
		var spot: Vector2 = _region_spots[id]
		flat = maxf(flat, 1.0 - smoothstep(FLAT_RADIUS, FLAT_RADIUS + FLAT_FALLOFF, here.distance_to(spot)))
	for road in _roads:
		var info: Dictionary = road
		var bounds: Rect2 = info["bounds"]
		if not bounds.has_point(here):
			continue
		var path: PackedVector2Array = info["path"]
		flat = maxf(flat, 1.0 - smoothstep(ROAD_FLAT_WIDTH, ROAD_FLAT_WIDTH + ROAD_FLAT_FALLOFF,
				_distance_to_path(here, path)))
	return lerpf(h, GROUND_Y, flat)


## Color del terreno: césped de base, el color de cada región cerca de su plataforma, roca y nieve en
## las cumbres, playa en la costa y fondo marino bajo el agua.
static func color_at(x: float, z: float, y: float) -> Color:
	if not _layout_ready:
		prepare_layout()
	var color := Color(0.43, 0.66, 0.33)
	var here := Vector2(x, z)
	for id in _region_ids:
		var spot: Vector2 = _region_spots[id]
		var ratio: float = here.distance_to(spot) / BIOME_RADIUS
		var weight: float = exp(-ratio * ratio * 1.6)
		var ground: Color = _region_colors[id]
		color = color.lerp(ground, clampf(weight * 1.15, 0.0, 1.0))
	if y > 7.0:
		color = color.lerp(Color(0.52, 0.47, 0.42), clampf((y - 7.0) / 3.0, 0.0, 1.0))
	if y > 12.5:
		color = color.lerp(Color(0.95, 0.96, 0.98), clampf((y - 12.5) / 2.0, 0.0, 1.0))
	if y < SEA_Y + 1.1:
		color = color.lerp(Color(0.89, 0.80, 0.58), clampf((SEA_Y + 1.1 - y) / 0.9, 0.0, 1.0))
	if y < SEA_Y - 0.4:
		color = color.lerp(Color(0.16, 0.42, 0.52), clampf((SEA_Y - 0.4 - y) / 1.8, 0.0, 1.0))
	var shade: float = 0.045 * sin(x * 0.83 + z * 0.37) * cos(z * 0.71 - x * 0.19)
	return Color(clampf(color.r + shade, 0.0, 1.0), clampf(color.g + shade, 0.0, 1.0),
			clampf(color.b + shade, 0.0, 1.0), 1.0)


# ---------------------------------------------------------------- Construcción

## Construye todo el mapa. "quality" es SettingsManager.Quality (0 baja, 1 media, 2 alta).
func build(quality: int = 1) -> void:
	_clear()
	_quality = quality
	_density = SceneryKit.density(quality)
	prepare_layout()
	_make_materials()
	_build_environment()
	_build_terrain()
	_build_sea()
	_build_roads()
	_build_regions()
	_build_arrow()
	_build_life()
	_refresh_roads()
	set_process(true)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_regions = {}
	_road_nodes = []
	selected_id = ""
	next_id = ""
	_time = 0.0


func _make_materials() -> void:
	_model_day = _tinted(null, Color.WHITE)
	_model_night = _tinted(null, COLOR_NIGHT)
	_model_locked = _tinted(null, COLOR_LOCKED)
	var cobble: ImageTexture = TextureKit.texture("cobble")
	_pad_day = _tinted(cobble, Color.WHITE)
	_pad_locked = _tinted(cobble, COLOR_LOCKED)
	var dirt: ImageTexture = TextureKit.texture("dirt")
	_road_open = _tinted(dirt, Color.WHITE)
	_road_closed = _tinted(dirt, Color(0.55, 0.57, 0.64))


## Material de colores por vértice con un tinte general (y una textura si se da).
func _tinted(texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if texture != null:
		m.albedo_texture = texture
		m.albedo_color = Color(tint.r * TextureKit.GAIN, tint.g * TextureKit.GAIN, tint.b * TextureKit.GAIN, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		m.albedo_color = tint
	return m


func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var environment: Environment = EnvFactory.create(Color(0.26, 0.54, 0.90), Color(0.90, 0.93, 0.86),
			Color(0.30, 0.46, 0.56), Color(1.0, 0.97, 0.90), Color(0.80, 0.89, 0.91), FOG_DENSITY,
			AMBIENT_ENERGY)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = environment
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.shadow_enabled = false
	var sun_in_sky: Vector3 = Vector3(-0.5, 0.78, 0.45).normalized()
	sun.transform = Transform3D(Basis.looking_at(-sun_in_sky, Vector3.UP), Vector3.ZERO)
	add_child(sun)


## El terreno tarda un poco en calcularse, así que se calcula una sola vez por sesión.
func _build_terrain() -> void:
	if _terrain_mesh == null:
		_terrain_mesh = TerrainKit.build(HALF, CELLS, height_at, color_at, 0.12)
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = _terrain_mesh
	node.material_override = TextureKit.material("grass", 1.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_sea() -> void:
	var kit := MeshKit.new()
	kit.disc(Vector3(0.0, SEA_Y, 0.0), 520.0, Color.WHITE, 56)
	add_child(kit.instance(WaterKit.water_material(Color(0.06, 0.30, 0.48, 0.95),
			Color(0.24, 0.64, 0.76, 0.86), 0.45, 0.45, 0.0), "Sea"))


func _build_roads() -> void:
	_roads_root = Node3D.new()
	_roads_root.name = "Roads"
	add_child(_roads_root)
	for i in _roads.size():
		var info: Dictionary = _roads[i]
		var path: PackedVector2Array = info["path"]
		var kit := MeshKit.new()
		var glow := MeshKit.new()
		kit.uv_scale = 0.35
		_add_road(kit, glow, path)
		var road: MeshInstance3D = kit.instance(_road_closed, "Road_%d" % i)
		var dashes: MeshInstance3D = glow.instance(TextureKit.glow_vertex(true), "RoadGlow_%d" % i)
		dashes.visible = false
		_roads_root.add_child(road)
		_roads_root.add_child(dashes)
		_road_nodes.append({"from": str(info["from"]), "to": str(info["to"]), "road": road, "glow": dashes})


## Cinta de tierra con piedras en los bordes, y destellos dorados en el centro (en otra malla).
func _add_road(kit: MeshKit, glow: MeshKit, path: PackedVector2Array) -> void:
	var count: int = path.size()
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in count:
		var tangent: Vector2
		if i == 0:
			tangent = path[1] - path[0]
		elif i == count - 1:
			tangent = path[count - 1] - path[count - 2]
		else:
			tangent = path[i + 1] - path[i - 1]
		tangent = tangent.normalized()
		var side: Vector2 = Vector2(-tangent.y, tangent.x) * ROAD_HALF_WIDTH
		lefts.append(Vector3(path[i].x - side.x, ROAD_Y, path[i].y - side.y))
		rights.append(Vector3(path[i].x + side.x, ROAD_Y, path[i].y + side.y))
	for i in count - 1:
		var tint := Color(0.84, 0.72, 0.50)
		if i % 2 == 1:
			tint = Color(0.80, 0.68, 0.46)
		kit.quad(lefts[i], lefts[i + 1], rights[i + 1], rights[i], tint, Vector3.UP)
	var stone := Color(0.66, 0.62, 0.56)
	for i in range(1, count - 1, 2):
		kit.box(lefts[i] + Vector3(0.0, 0.12, 0.0), Vector3(0.5, 0.26, 0.5), stone)
		kit.box(rights[i] + Vector3(0.0, 0.12, 0.0), Vector3(0.5, 0.26, 0.5), stone.darkened(0.06))
	for i in count - 1:
		if i % 2 == 1:
			continue
		var from_point: Vector2 = path[i]
		var to_point: Vector2 = path[i + 1]
		var middle: Vector2 = (from_point + to_point) * 0.5
		var direction: Vector2 = to_point - from_point
		glow.place(Vector3(middle.x, ROAD_Y + 0.08, middle.y), atan2(direction.x, direction.y))
		glow.box(Vector3.ZERO, Vector3(0.42, 0.06, 0.95), Color(1.0, 0.84, 0.34, 0.9))
		glow.pop()


func _build_regions() -> void:
	_regions_root = Node3D.new()
	_regions_root.name = "Regions"
	add_child(_regions_root)
	var index: int = 0
	for entry in MapCatalog.all_maps():
		var map_data: Dictionary = entry
		_build_region(map_data, index)
		index += 1


func _build_region(map_data: Dictionary, index: int) -> void:
	var id: String = str(map_data["id"])
	var theme_data: Dictionary = map_data["theme"]
	var world: Dictionary = map_data["world"]
	var board: Dictionary = map_data["board"]
	var icon_name: String = str(world["icon"])
	var spot: Vector2 = _region_spots[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mundo:" + id)

	var region := RegionNode.new()
	region.id = id
	region.phase = float(index) * 1.3
	region.night = BoardStyle.is_night(str(board["style"]))
	var root := Node3D.new()
	root.name = "Region_" + id
	root.position = Vector3(spot.x, PAD_Y, spot.y)
	_regions_root.add_child(root)
	region.root = root

	# Plataforma de la región, con los colores de su tablero.
	var pad := MeshKit.new()
	pad.uv_scale = 0.3
	var top_color: Color = _theme_color(theme_data, "tile_a", Color(0.90, 0.80, 0.60))
	var rim_color: Color = _theme_color(theme_data, "frame", Color(0.42, 0.27, 0.15))
	pad.cylinder(Vector3(0.0, -1.7, 0.0), PAD_RADIUS + 0.4, PAD_RADIUS, 1.7, 32, rim_color, true, false, top_color)
	pad.place(Vector3(0.0, 0.03, 0.0))
	WorldIcons.add_ring(pad, PAD_RADIUS - 0.7, 0.12, rim_color.lightened(0.12), 32)
	pad.pop()
	region.pad = pad.instance(_pad_day, "Pad")
	root.add_child(region.pad)
	if icon_name == "ark":
		var pond := MeshKit.new()
		pond.disc(Vector3(0.0, 0.06, 0.0), 6.4, Color.WHITE, 28)
		root.add_child(pond.instance(WaterKit.water_material(Color(0.07, 0.30, 0.50, 0.95),
				Color(0.28, 0.62, 0.76, 0.88), 0.5, 0.6, 0.0), "Pond"))

	# Decorado alrededor y el icono en el centro.
	var decor := MeshKit.new()
	var decor_glow := MeshKit.new()
	WorldIcons.add_decor(decor, decor_glow, icon_name, rng, _density)
	region.decor = decor.instance(_model_day, "Decor")
	root.add_child(region.decor)
	if not decor_glow.is_empty():
		region.decor_glow = decor_glow.instance(TextureKit.glow_vertex(true), "DecorGlow")
		root.add_child(region.decor_glow)
	var icon_kit := MeshKit.new()
	var icon_glow := MeshKit.new()
	region.top = WorldIcons.add_icon(icon_kit, icon_glow, icon_name, rng)
	region.icon = Node3D.new()
	region.icon.name = "Icon"
	root.add_child(region.icon)
	region.icon_mesh = icon_kit.instance(_model_day, "Model")
	region.icon.add_child(region.icon_mesh)
	if not icon_glow.is_empty():
		region.icon_glow = icon_glow.instance(TextureKit.glow_vertex(true), "Glow")
		region.icon.add_child(region.icon_glow)

	# Figuras de estado.
	var lock_kit := MeshKit.new()
	WorldIcons.add_padlock(lock_kit)
	region.lock = lock_kit.instance(TextureKit.plain(0.45), "Lock")
	region.lock.scale = Vector3.ONE * LOCK_SCALE
	region.lock.position = Vector3(0.0, region.top + 1.4, 0.0)
	root.add_child(region.lock)
	region.halo = _ring_node("Halo", PAD_RADIUS - 0.8, Color(1.0, 0.86, 0.38, 0.85), Color(1.0, 0.92, 0.55, 0.4), 0.3)
	root.add_child(region.halo)
	region.done_ring = _ring_node("DoneRing", PAD_RADIUS - 0.8, Color(0.5, 1.0, 0.58, 0.85), Color(0.7, 1.0, 0.7, 0.4), 0.3)
	root.add_child(region.done_ring)
	var star_kit := MeshKit.new()
	WorldIcons.add_star(star_kit, 1.5)
	region.star = star_kit.instance(TextureKit.glow_vertex(true), "Star")
	region.star.position = Vector3(0.0, region.top + 3.0, 0.0)
	root.add_child(region.star)
	region.selector = _ring_node("Selector", PAD_RADIUS + 1.6, Color(1.0, 1.0, 1.0, 0.9), Color(1.0, 0.88, 0.4, 0.6), -0.2)
	root.add_child(region.selector)

	region.label = Label3D.new()
	region.label.name = "Label"
	region.label.text = str(map_data["name"])
	region.label.font_size = 64
	region.label.pixel_size = 0.0105
	region.label.outline_size = 16
	region.label.outline_modulate = Color(0.10, 0.06, 0.02, 0.95)
	region.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	region.label.shaded = false
	region.label.no_depth_test = true
	region.label.render_priority = 10
	region.label.outline_render_priority = 9
	region.label.position = Vector3(0.0, region.top + LABEL_LIFT, 0.0)
	region.label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(region.label)

	_regions[id] = region
	set_status(id, ProgressData.STATUS_LOCKED)


## Aro de luz plano sobre la plataforma (con otro aro más fino por dentro o por fuera).
func _ring_node(node_name: String, radius: float, color: Color, inner_color: Color,
		lift: float) -> MeshInstance3D:
	var kit := MeshKit.new()
	kit.place(Vector3(0.0, lift, 0.0))
	WorldIcons.add_ring(kit, radius, 0.24, color, 32)
	WorldIcons.add_ring(kit, radius - 0.9, 0.12, inner_color, 32)
	kit.pop()
	var node: MeshInstance3D = kit.instance(TextureKit.glow_vertex(true), node_name)
	node.visible = false
	return node


func _build_arrow() -> void:
	var kit := MeshKit.new()
	WorldIcons.add_arrow(kit)
	_arrow = kit.instance(TextureKit.glow_vertex(true), "NextArrow")
	_arrow.visible = false
	add_child(_arrow)


## Nubes lejanas, aves y partículas en algunas regiones (polen, polvo, chispas, luciérnagas).
func _build_life() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	FxKit.clouds(self, rng, 4 if _quality <= 0 else 6, 30.0, 42.0, 260.0, Color(1.0, 1.0, 1.0, 0.82))
	FxKit.birds(self, rng, 2 if _quality <= 0 else 3, Vector3(0.0, 0.0, -4.0), 52.0, 24.0, Color(0.99, 0.99, 0.96))
	var amount: float = _density
	_floaters("tree", "PolenEden", Vector3(0.0, 4.5, 0.0), Vector3(9.0, 3.0, 9.0), int(24.0 * amount), 0.55,
			Color(1.0, 0.95, 0.55, 0.9), 0.03, 7.0, true)
	_floaters("tent", "PolvoDesierto", Vector3(0.0, 2.0, 0.0), Vector3(9.0, 2.0, 9.0), int(14.0 * amount), 2.2,
			Color(0.95, 0.80, 0.55, 0.4), 0.02, 8.0, false)
	_floaters("mountain", "ChispasSinai", Vector3(0.0, 11.0, 0.0), Vector3(3.0, 5.0, 3.0), int(26.0 * amount),
			0.6, Color(1.0, 0.88, 0.45, 0.9), 0.2, 5.0, true)
	_floaters("stable", "LuciernagasBelen", Vector3(0.0, 2.5, 0.0), Vector3(9.0, 2.5, 9.0), int(20.0 * amount),
			0.4, Color(1.0, 0.92, 0.5, 0.95), 0.01, 6.0, true)


func _floaters(icon_name: String, node_name: String, offset: Vector3, extents: Vector3, amount: int,
		size: float, color: Color, rise: float, lifetime: float, additive: bool) -> void:
	for entry in MapCatalog.all_maps():
		var map_data: Dictionary = entry
		var world: Dictionary = map_data["world"]
		if str(world["icon"]) != icon_name:
			continue
		var region: RegionNode = _regions.get(str(map_data["id"]))
		if region == null:
			return
		FxKit.floaters(self, node_name, region.root.position + offset, extents, maxi(4, amount), size, color,
				rise, lifetime, additive)


func _theme_color(theme_data: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = theme_data.get(key, fallback)
	if value is Color:
		return value
	return fallback


# ---------------------------------------------------------------- Consultas

func region_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_region_ids)
	return ids


func has_region(map_id: String) -> bool:
	return _regions.has(map_id)


## Centro de la plataforma de la región, en el mundo 3D.
func region_position(map_id: String) -> Vector3:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return Vector3.ZERO
	return region.root.position


## Punto donde se toca la región (hacia la mitad de la altura del icono): sirve para elegirla con
## el dedo y para centrar la cámara.
func focus_point(map_id: String) -> Vector3:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return Vector3.ZERO
	return region.root.position + Vector3(0.0, region.top * 0.45, 0.0)


## "locked", "available" o "completed" (lo que se está mostrando).
func status_of(map_id: String) -> String:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return ""
	return region.status


func is_lock_visible(map_id: String) -> bool:
	var region: RegionNode = _regions.get(map_id)
	return region != null and region.lock.visible


func is_halo_visible(map_id: String) -> bool:
	var region: RegionNode = _regions.get(map_id)
	return region != null and region.halo.visible


func is_star_visible(map_id: String) -> bool:
	var region: RegionNode = _regions.get(map_id)
	return region != null and region.star.visible


func is_selector_visible(map_id: String) -> bool:
	var region: RegionNode = _regions.get(map_id)
	return region != null and region.selector.visible


func is_arrow_visible() -> bool:
	return _arrow != null and _arrow.visible


## Verdadero si el camino que llega a esta región (desde la anterior) está abierto.
func is_road_open(map_id: String) -> bool:
	for info in _road_nodes:
		var entry: Dictionary = info
		if str(entry["to"]) == map_id:
			return (entry["glow"] as MeshInstance3D).visible
	return false


func road_nodes() -> Array:
	return _road_nodes


func label_of(map_id: String) -> Label3D:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return null
	return region.label


## Altura del icono de la región (sin contar el rótulo).
func icon_height(map_id: String) -> float:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return 0.0
	return region.top


# ---------------------------------------------------------------- Estados y animaciones

## Muestra la región como bloqueada, abierta o completada.
func set_status(map_id: String, status: String) -> void:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return
	region.status = status
	var locked: bool = status == ProgressData.STATUS_LOCKED
	var done: bool = status == ProgressData.STATUS_COMPLETED
	var model: StandardMaterial3D = _model_day
	if locked:
		model = _model_locked
	elif region.night:
		model = _model_night
	region.icon_mesh.material_override = model
	region.decor.material_override = model
	region.pad.material_override = _pad_locked if locked else _pad_day
	if region.icon_glow != null:
		region.icon_glow.visible = not locked
	if region.decor_glow != null:
		region.decor_glow.visible = not locked
	region.lock.visible = locked
	region.lock.scale = Vector3.ONE * LOCK_SCALE
	region.halo.visible = status == ProgressData.STATUS_AVAILABLE
	region.done_ring.visible = done
	region.star.visible = done
	if locked:
		region.label.modulate = Color(0.78, 0.80, 0.88)
	elif done:
		region.label.modulate = Color(0.74, 1.0, 0.78)
	else:
		region.label.modulate = Color(1.0, 0.94, 0.70)
	_refresh_roads()
	_refresh_arrow()


## Marca la región elegida: aro blanco y un pequeño salto del icono (si "animate").
func set_selected(map_id: String, animate: bool = true) -> void:
	selected_id = map_id
	for id in _regions:
		var region: RegionNode = _regions[id]
		region.selector.visible = str(id) == map_id
	if animate and not map_id.is_empty():
		pop_region(map_id)


## Región recomendada (la próxima que hay que jugar); la flecha dorada se queda sobre ella.
func set_next(map_id: String) -> void:
	next_id = map_id
	_refresh_arrow()


func _refresh_arrow() -> void:
	if _arrow == null:
		return
	var region: RegionNode = _regions.get(next_id)
	if region == null or region.status != ProgressData.STATUS_AVAILABLE:
		_arrow.visible = false
		return
	_arrow.position = region.root.position + Vector3(0.0, region.top + ARROW_LIFT, 0.0)
	_arrow.visible = true


func _refresh_roads() -> void:
	for info in _road_nodes:
		var entry: Dictionary = info
		var to_region: RegionNode = _regions.get(str(entry["to"]))
		var open: bool = to_region != null and to_region.status != ProgressData.STATUS_LOCKED
		(entry["road"] as MeshInstance3D).material_override = _road_open if open else _road_closed
		(entry["glow"] as MeshInstance3D).visible = open


## El icono salta y se asienta, y el aro de selección crece.
func pop_region(map_id: String) -> void:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return
	for old in region.pop_tweens:
		var previous: Tween = old
		if previous != null and previous.is_valid():
			previous.kill()
	region.pop_tweens = []
	region.icon.scale = Vector3.ONE
	if not is_inside_tree():
		region.selector.scale = Vector3.ONE
		return
	region.selector.scale = Vector3(0.7, 1.0, 0.7)
	var grow: Tween = create_tween()
	grow.tween_property(region.selector, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bounce: Tween = create_tween()
	bounce.tween_property(region.icon, "scale", Vector3(1.22, 1.22, 1.22), 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(region.icon, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	region.pop_tweens = [grow, bounce]


## El candado sacude un poco (se tocó una región bloqueada).
func shake_lock(map_id: String) -> void:
	var region: RegionNode = _regions.get(map_id)
	if region == null or not region.lock.visible or not is_inside_tree():
		return
	var tween: Tween = create_tween()
	tween.tween_property(region.lock, "rotation:z", 0.4, 0.06)
	tween.tween_property(region.lock, "rotation:z", -0.4, 0.1)
	tween.tween_property(region.lock, "rotation:z", 0.2, 0.08)
	tween.tween_property(region.lock, "rotation:z", 0.0, 0.08)


## Se abre una región: el candado salta, crece y desaparece entre chispas; luego se muestra abierta.
func play_unlock(map_id: String) -> void:
	var region: RegionNode = _regions.get(map_id)
	if region == null:
		return
	if not is_inside_tree():
		set_status(map_id, ProgressData.STATUS_AVAILABLE)
		return
	region.lock.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(region.lock, "scale", Vector3.ONE * LOCK_SCALE * 1.45, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(region.lock, "scale", Vector3(0.01, 0.01, 0.01), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(set_status.bind(map_id, ProgressData.STATUS_AVAILABLE))
	_burst(region.root.position + Vector3(0.0, region.top + 3.0, 0.0), GOLD)


## Explosión de chispas (una sola vez); se borra sola.
func _burst(at: Vector3, color: Color) -> void:
	if not is_inside_tree():
		return
	var particles := CPUParticles3D.new()
	particles.name = "Burst"
	particles.one_shot = true
	particles.amount = 40
	particles.lifetime = 1.6
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 12.0
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.4
	particles.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	particles.mesh = quad
	particles.material_override = TextureKit.particle_material(true)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = at
	add_child(particles)
	particles.emitting = true
	var cleanup: Tween = particles.create_tween()
	cleanup.tween_interval(3.0)
	cleanup.tween_callback(particles.queue_free)


## Los rótulos mantienen más o menos el mismo tamaño en pantalla a cualquier distancia de la cámara.
func update_label_scale(camera_distance: float) -> void:
	var factor: float = clampf(camera_distance * 0.038, 0.9, 4.6)
	for id in _regions:
		var region: RegionNode = _regions[id]
		region.label.scale = Vector3(factor, factor, factor)


func _process(delta: float) -> void:
	_time += delta
	for id in _regions:
		var region: RegionNode = _regions[id]
		var t: float = _time + region.phase
		if region.lock.visible:
			region.lock.position.y = region.top + 1.4 + sin(t * 1.7) * 0.25
			region.lock.rotation.y = sin(t * 0.9) * 0.25
		if region.halo.visible:
			var pulse: float = 1.0 + 0.05 * sin(t * 2.4)
			region.halo.scale = Vector3(pulse, 1.0, pulse)
		if region.star.visible:
			region.star.position.y = region.top + 3.0 + sin(t * 1.9) * 0.3
		if region.selector.visible:
			region.selector.rotation.y = t * 0.5
	if _arrow != null and _arrow.visible:
		var next_region: RegionNode = _regions.get(next_id)
		if next_region != null:
			_arrow.position.y = next_region.top + ARROW_LIFT + sin(_time * 2.6) * 0.5
