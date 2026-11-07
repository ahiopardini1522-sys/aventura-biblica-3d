class_name BoardBuilder
extends Node3D
## Construye el tablero 3D completo (marco, casillas con número, escaleras, serpientes,
## punto de inicio, meta y zona del dado) a partir de un BoardLayout y los colores del mapa.
## Todo son primitivas creadas por código: cuando existan modelos reales en assets/models
## solo habrá que sustituir las piezas correspondientes.

const START_COLOR := Color(0.30, 0.72, 0.40)
const GOAL_COLOR := Color(0.96, 0.77, 0.33)
const LADDER_TINT := Color(0.50, 0.78, 0.35)
const SNAKE_TINT := Color(0.88, 0.36, 0.30)
const WOOD_COLOR := Color(0.58, 0.38, 0.19)
const LADDER_WIDTH := 0.44
const SHADOW_REACH := 1.6
const SNAKE_COLORS := [
	Color(0.30, 0.65, 0.30),
	Color(0.82, 0.50, 0.20),
	Color(0.58, 0.36, 0.72),
	Color(0.20, 0.60, 0.64),
	Color(0.80, 0.28, 0.25),
	Color(0.62, 0.64, 0.22),
	Color(0.30, 0.40, 0.66),
]

var layout: BoardLayout

var _theme: Dictionary = {}
var _materials: Dictionary = {}
var _tiles_root: Node3D
var _ladders_root: Node3D
var _snakes_root: Node3D
var _dice_area: Node3D


## Crea todo el tablero. Si ya había uno construido, lo reemplaza.
func build(new_layout: BoardLayout, theme_data: Dictionary) -> void:
	clear()
	layout = new_layout
	_theme = theme_data
	_build_contact_shadow()
	_build_frame()
	_build_tiles()
	_build_ladders()
	_build_snakes()
	_build_start_marker()
	_build_goal_marker()
	_build_dice_area()


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_materials.clear()
	_tiles_root = null
	_ladders_root = null
	_snakes_root = null
	_dice_area = null


# ---------------------------------------------------------------- Consultas

func tile_count() -> int:
	return _tiles_root.get_child_count() if _tiles_root != null else 0


func ladder_count() -> int:
	return _ladders_root.get_child_count() if _ladders_root != null else 0


func snake_count() -> int:
	return _snakes_root.get_child_count() if _snakes_root != null else 0


## Nodo de una casilla (1 a N), o null si no existe.
func tile_node(tile: int) -> MeshInstance3D:
	if _tiles_root == null:
		return null
	return _tiles_root.get_node_or_null("Tile_%03d" % tile) as MeshInstance3D


## Centro de la cara superior de una casilla, en el espacio del tablero.
func tile_position(tile: int) -> Vector3:
	return layout.tile_center(tile)


## Punto donde se apoya el dado (sobre su pedestal).
func dice_position() -> Vector3:
	return _dice_area.position if _dice_area != null else Vector3.ZERO


# ---------------------------------------------------------------- Marco y casillas

## Sombra suave bajo el tablero y la zona del dado, para que se vean apoyados en el suelo.
func _build_contact_shadow() -> void:
	var size: Vector2 = layout.board_size()
	var reach: float = SHADOW_REACH
	var plane := PlaneMesh.new()
	# Cubre el tablero, el marco y la zona del dado (que queda a la derecha).
	var dice_extra: float = 5.6
	plane.size = Vector2(size.x + BoardLayout.FRAME_MARGIN * 2.0 + reach * 2.0 + dice_extra,
			size.y + BoardLayout.FRAME_MARGIN * 2.0 + reach * 2.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _soft_shadow_texture()
	material.albedo_color = Color(0.10, 0.05, 0.02, 0.62)
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = plane
	shadow.material_override = material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El suelo del entorno tiene su cara superior en y = -0.3; la sombra queda justo encima.
	shadow.position = Vector3(dice_extra * 0.5, -0.29, 0.0)
	add_child(shadow)


## Textura cuadrada con el centro opaco y los bordes transparentes (esquinas redondeadas).
func _soft_shadow_texture() -> ImageTexture:
	var pixels: int = 64
	var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	for y in pixels:
		for x in pixels:
			var u: float = (float(x) + 0.5) / float(pixels) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(pixels) * 2.0 - 1.0
			var distance: float = pow(pow(absf(u), 4.0) + pow(absf(v), 4.0), 0.25)
			var alpha: float = 1.0 - smoothstep(0.62, 1.0, distance)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _build_frame() -> void:
	var size: Vector2 = layout.board_size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x + BoardLayout.FRAME_MARGIN * 2.0, BoardLayout.FRAME_THICKNESS,
			size.y + BoardLayout.FRAME_MARGIN * 2.0)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = mesh
	frame.material_override = _material("frame", _color("frame", Color(0.42, 0.27, 0.15)), 0.9)
	frame.position = Vector3(0.0, -BoardLayout.FRAME_THICKNESS * 0.5, 0.0)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)


func _build_tiles() -> void:
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(BoardLayout.TILE_SIZE, BoardLayout.TILE_HEIGHT, BoardLayout.TILE_SIZE)
	var color_a: Color = _color("tile_a", Color(0.92, 0.82, 0.60))
	var color_b: Color = _color("tile_b", Color(0.84, 0.65, 0.40))

	for tile in range(1, layout.tile_count() + 1):
		var cell: Vector2i = layout.grid_of(tile)
		var base: Color = color_a if (cell.x + cell.y) % 2 == 0 else color_b
		var color: Color = _tile_color(tile, base)
		var center: Vector3 = layout.tile_center(tile)

		var instance := MeshInstance3D.new()
		instance.name = "Tile_%03d" % tile
		instance.mesh = tile_mesh
		instance.material_override = _material("tile_" + color.to_html(false), color, 0.85)
		instance.position = Vector3(center.x, BoardLayout.TILE_HEIGHT * 0.5, center.z)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_meta(&"tile", tile)
		_tiles_root.add_child(instance)
		instance.add_child(_make_number(tile, color))


## Color de una casilla: normal, inicio, meta o el matiz de escalera/serpiente.
func _tile_color(tile: int, base: Color) -> Color:
	if tile == 1:
		return START_COLOR
	if tile == layout.tile_count():
		return GOAL_COLOR
	match _tile_role(tile):
		"ladder_start", "ladder_end":
			return base.lerp(LADDER_TINT, 0.5)
		"snake_head", "snake_tail":
			return base.lerp(SNAKE_TINT, 0.45)
	return base


func _tile_role(tile: int) -> String:
	for pair in layout.ladders:
		if pair.x == tile:
			return "ladder_start"
		if pair.y == tile:
			return "ladder_end"
	for pair in layout.snakes:
		if pair.x == tile:
			return "snake_head"
		if pair.y == tile:
			return "snake_tail"
	return ""


## Número de la casilla, tendido sobre la cara superior y legible desde la cámara.
func _make_number(tile: int, tile_color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "Number"
	label.text = str(tile)
	label.font_size = 56
	label.pixel_size = 0.0042
	label.shaded = false
	label.double_sided = false
	label.modulate = Color(0.16, 0.10, 0.05) if tile_color.get_luminance() > 0.42 else Color(0.97, 0.94, 0.86)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	label.position = Vector3(-0.17, BoardLayout.TILE_HEIGHT * 0.5 + 0.01, 0.2)
	return label


# ---------------------------------------------------------------- Escaleras

func _build_ladders() -> void:
	_ladders_root = Node3D.new()
	_ladders_root.name = "Ladders"
	add_child(_ladders_root)

	var wood: StandardMaterial3D = _material("wood", WOOD_COLOR, 0.8)
	var rung_mesh := BoxMesh.new()
	rung_mesh.size = Vector3(LADDER_WIDTH + 0.08, 0.05, 0.07)

	for pair in layout.ladders:
		var from_pos: Vector3 = layout.tile_center(pair.x)
		var to_pos: Vector3 = layout.tile_center(pair.y)
		var delta: Vector3 = to_pos - from_pos
		var length: float = delta.length()
		var middle: Vector3 = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.07, 0.0)

		var ladder := Node3D.new()
		ladder.name = "Ladder_%03d_%03d" % [pair.x, pair.y]
		ladder.transform = Transform3D(Basis.looking_at(delta / length, Vector3.UP), middle)
		_ladders_root.add_child(ladder)

		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.07, 0.09, length)
		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			rail.name = "Rail"
			rail.mesh = rail_mesh
			rail.material_override = wood
			rail.position = Vector3(float(side) * LADDER_WIDTH * 0.5, 0.0, 0.0)
			ladder.add_child(rail)

		var rung_count: int = maxi(2, int(length / 0.42))
		for i in rung_count:
			var rung := MeshInstance3D.new()
			rung.name = "Rung"
			rung.mesh = rung_mesh
			rung.material_override = wood
			var t: float = (float(i) + 0.5) / float(rung_count)
			rung.position = Vector3(0.0, 0.0, -length * 0.5 + t * length)
			ladder.add_child(rung)


# ---------------------------------------------------------------- Serpientes

func _build_snakes() -> void:
	_snakes_root = Node3D.new()
	_snakes_root.name = "Snakes"
	add_child(_snakes_root)
	var index: int = 0
	for pair in layout.snakes:
		var color: Color = SNAKE_COLORS[index % SNAKE_COLORS.size()]
		_snakes_root.add_child(_make_snake(pair.x, pair.y, color))
		index += 1


## Una serpiente: cuerpo ondulado (tubo) desde la cabeza, en la casilla alta,
## hasta la cola, en la casilla baja, más cabeza, ojos y lengua.
func _make_snake(head_tile: int, tail_tile: int, color: Color) -> Node3D:
	var head_pos: Vector3 = layout.tile_center(head_tile)
	var tail_pos: Vector3 = layout.tile_center(tail_tile)
	var flat := Vector3(tail_pos.x - head_pos.x, 0.0, tail_pos.z - head_pos.z)
	var length: float = flat.length()
	var direction: Vector3 = flat / length
	var side := Vector3(-direction.z, 0.0, direction.x)
	var segments: int = clampi(int(length * 5.0), 14, 80)
	var waves: float = maxf(1.0, roundf(length / 2.4))

	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var along: Vector3 = head_pos.lerp(tail_pos, t)
		var wiggle: float = sin(t * TAU * waves) * 0.34 * sin(t * PI)
		var radius: float = 0.13 * lerpf(1.0, 0.2, pow(t, 1.4))
		points.append(Vector3(along.x, BoardLayout.TILE_HEIGHT + radius, along.z) + side * wiggle)
		radii.append(radius)
		var band: int = int(float(i) / 2.0) % 2
		colors.append(color if band == 0 else color.darkened(0.28))

	var snake := Node3D.new()
	snake.name = "Snake_%03d_%03d" % [head_tile, tail_tile]

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshFactory.tube(points, radii, colors, 8)
	body.material_override = _vertex_material()
	snake.add_child(body)

	var head_direction: Vector3 = (points[0] - points[1]).normalized()
	var head := Node3D.new()
	head.name = "Head"
	head.transform = Transform3D(Basis.looking_at(head_direction, Vector3.UP),
			Vector3(head_pos.x, BoardLayout.TILE_HEIGHT, head_pos.z))
	snake.add_child(head)
	_add_snake_head_parts(head, color)
	return snake


func _add_snake_head_parts(head: Node3D, color: Color) -> void:
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.19
	skull_mesh.height = 0.38
	skull_mesh.radial_segments = 14
	skull_mesh.rings = 8
	var skull := MeshInstance3D.new()
	skull.name = "Skull"
	skull.mesh = skull_mesh
	skull.material_override = _material("snake_head_" + color.to_html(false), color.lightened(0.08), 0.5)
	skull.position = Vector3(0.0, 0.17, -0.05)
	skull.scale = Vector3(1.0, 0.8, 1.25)
	head.add_child(skull)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.06
	eye_mesh.height = 0.12
	eye_mesh.radial_segments = 8
	eye_mesh.rings = 4
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.032
	pupil_mesh.height = 0.064
	pupil_mesh.radial_segments = 6
	pupil_mesh.rings = 3
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye"
		eye.mesh = eye_mesh
		eye.material_override = _material("eye_white", Color(0.98, 0.98, 0.94), 0.3)
		eye.position = Vector3(float(side) * 0.11, 0.28, -0.12)
		head.add_child(eye)
		var pupil := MeshInstance3D.new()
		pupil.name = "Pupil"
		pupil.mesh = pupil_mesh
		pupil.material_override = _material("eye_black", Color(0.05, 0.04, 0.04), 0.3)
		pupil.position = Vector3(float(side) * 0.11, 0.29, -0.17)
		head.add_child(pupil)

	var tongue_mat: StandardMaterial3D = _material("tongue", Color(0.88, 0.12, 0.18), 0.5)
	var tongue_mesh := BoxMesh.new()
	tongue_mesh.size = Vector3(0.035, 0.012, 0.26)
	var tongue := MeshInstance3D.new()
	tongue.name = "Tongue"
	tongue.mesh = tongue_mesh
	tongue.material_override = tongue_mat
	tongue.position = Vector3(0.0, 0.1, -0.4)
	head.add_child(tongue)
	var prong_mesh := BoxMesh.new()
	prong_mesh.size = Vector3(0.03, 0.012, 0.12)
	for side in [-1.0, 1.0]:
		var prong := MeshInstance3D.new()
		prong.name = "TongueProng"
		prong.mesh = prong_mesh
		prong.material_override = tongue_mat
		prong.position = Vector3(float(side) * 0.04, 0.1, -0.56)
		prong.rotation = Vector3(0.0, float(side) * 0.45, 0.0)
		head.add_child(prong)


# ---------------------------------------------------------------- Inicio, meta y dado

func _build_start_marker() -> void:
	var start: Vector3 = layout.tile_center(1)
	var root := Node3D.new()
	root.name = "StartMarker"
	root.position = Vector3(start.x - (BoardLayout.TILE_SIZE * 0.5 + 0.2), 0.0, start.z + 0.1)
	add_child(root)

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.1
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 1
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = pole_mesh
	pole.material_override = _material("pole", Color(0.85, 0.82, 0.74), 0.5)
	pole.position = Vector3(0.0, 1.05, 0.0)
	root.add_child(pole)

	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.62, 0.34, 0.04)
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	flag.mesh = flag_mesh
	flag.material_override = _material("flag", START_COLOR, 0.7)
	flag.position = Vector3(0.33, 1.85, 0.0)
	root.add_child(flag)

	root.add_child(_make_billboard("INICIO", Vector3(0.3, 2.5, 0.0), Color(0.80, 1.0, 0.82)))


func _build_goal_marker() -> void:
	var goal: Vector3 = layout.tile_center(layout.tile_count())
	var root := Node3D.new()
	root.name = "GoalMarker"
	root.position = goal
	add_child(root)

	var gold: StandardMaterial3D = _material("gold", GOAL_COLOR, 0.35, 0.6)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.08
	pillar_mesh.bottom_radius = 0.1
	pillar_mesh.height = 1.5
	pillar_mesh.radial_segments = 10
	pillar_mesh.rings = 1
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		pillar.name = "Pillar"
		pillar.mesh = pillar_mesh
		pillar.material_override = gold
		pillar.position = Vector3(float(side) * 0.42, 0.75, 0.0)
		root.add_child(pillar)

	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(1.1, 0.16, 0.2)
	var lintel := MeshInstance3D.new()
	lintel.name = "Lintel"
	lintel.mesh = lintel_mesh
	lintel.material_override = gold
	lintel.position = Vector3(0.0, 1.58, 0.0)
	root.add_child(lintel)

	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.17
	orb_mesh.height = 0.34
	orb_mesh.radial_segments = 12
	orb_mesh.rings = 6
	var orb := MeshInstance3D.new()
	orb.name = "Orb"
	orb.mesh = orb_mesh
	orb.material_override = MeshFactory.glow_material(Color(1.0, 0.86, 0.45, 0.95))
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position = Vector3(0.0, 1.92, 0.0)
	root.add_child(orb)

	root.add_child(_make_billboard("META", Vector3(0.0, 2.5, 0.0), Color(1.0, 0.92, 0.6)))


## Zona del dado: una plataforma redonda junto al tablero con un aro de luz.
func _build_dice_area() -> void:
	var size: Vector2 = layout.board_size()
	_dice_area = Node3D.new()
	_dice_area.name = "DiceArea"
	_dice_area.position = Vector3(size.x * 0.5 + BoardLayout.FRAME_MARGIN + 2.4, 0.0, 0.0)
	add_child(_dice_area)

	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 1.4
	pedestal_mesh.bottom_radius = 1.55
	pedestal_mesh.height = BoardLayout.FRAME_THICKNESS
	pedestal_mesh.radial_segments = 32
	pedestal_mesh.rings = 1
	var pedestal := MeshInstance3D.new()
	pedestal.name = "Pedestal"
	pedestal.mesh = pedestal_mesh
	pedestal.material_override = _material("frame", _color("frame", Color(0.42, 0.27, 0.15)), 0.9)
	pedestal.position = Vector3(0.0, -BoardLayout.FRAME_THICKNESS * 0.5, 0.0)
	_dice_area.add_child(pedestal)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.12
	ring_mesh.outer_radius = 1.26
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.name = "GlowRing"
	ring.mesh = ring_mesh
	ring.material_override = MeshFactory.glow_material(Color(1.0, 0.82, 0.4, 0.55))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position = Vector3(0.0, 0.02, 0.0)
	_dice_area.add_child(ring)


# ---------------------------------------------------------------- Ayudas

func _make_billboard(text: String, at: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0058
	label.outline_size = 16
	label.outline_modulate = Color(0.12, 0.07, 0.02, 0.95)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	return label


func _material(key: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if not _materials.has(key):
		_materials[key] = MeshFactory.material(color, roughness, metallic)
	return _materials[key]


func _vertex_material() -> StandardMaterial3D:
	if not _materials.has("snake_body"):
		_materials["snake_body"] = MeshFactory.vertex_color_material(0.55)
	return _materials["snake_body"]


func _color(key: String, fallback: Color) -> Color:
	var value: Variant = _theme.get(key, fallback)
	if value is Color:
		return value
	return fallback
