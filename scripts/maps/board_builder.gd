class_name BoardBuilder
extends Node3D
## Construye el tablero 3D completo (marco, casillas con número, escaleras, serpientes,
## punto de inicio, meta y zona del dado) a partir de un BoardLayout y los colores del mapa.
## Cada mapa tiene su propio estilo (layout.style, ver BoardStyle): otras losas, otro borde, otras
## puertas de salida y de meta, otras escaleras y serpientes. Todo son primitivas creadas por
## código y, para que vaya fluido en un móvil de gama media, se juntan en pocas mallas:
## todas las casillas en una, todos los números en otra, las marcas de desafío y de casillas
## especiales en otra, cada escalera en una y cada serpiente en dos (cuerpo y cabeza).

const START_COLOR := Color(0.30, 0.72, 0.40)
const GOAL_COLOR := Color(0.96, 0.77, 0.33)
const LADDER_TINT := Color(0.50, 0.78, 0.35)
const SNAKE_TINT := Color(0.88, 0.36, 0.30)
const CHALLENGE_TINT := Color(0.55, 0.52, 0.92)
const LADDER_LIFT := 0.14
const LADDER_WIDTH := 0.44
const SHADOW_REACH := 1.6

var layout: BoardLayout

var _theme: Dictionary = {}
var _style: String = "sand"
var _materials: Dictionary = {}
var _tiles_root: Node3D
var _ladders_root: Node3D
var _snakes_root: Node3D
var _dice_area: Node3D
var _challenge_marks: Dictionary = {}
var _special_marks: Dictionary = {}


## Crea todo el tablero. Si ya había uno construido, lo reemplaza.
func build(new_layout: BoardLayout, theme_data: Dictionary) -> void:
	clear()
	layout = new_layout
	_theme = theme_data
	_style = BoardStyle.normalize(layout.style)
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
	_challenge_marks.clear()
	_special_marks.clear()


# ---------------------------------------------------------------- Consultas

func tile_count() -> int:
	return _tiles_root.get_child_count() if _tiles_root != null else 0


func ladder_count() -> int:
	return _ladders_root.get_child_count() if _ladders_root != null else 0


func snake_count() -> int:
	return _snakes_root.get_child_count() if _snakes_root != null else 0


## Estilo con el que se construyó el tablero (garden, deck, causeway, sand, rock, city o village).
func board_style() -> String:
	return _style


## Ancla de una casilla (1 a N), sobre el centro de su cara superior, o null si no existe.
## La superficie de todas las casillas es una sola malla ("TileSurface"); el ancla sirve para
## colgar efectos o resaltar una casilla.
func tile_node(tile: int) -> Node3D:
	if _tiles_root == null:
		return null
	return _tiles_root.get_node_or_null("Tile_%03d" % tile) as Node3D


## Verdadero si la casilla lleva el disco dorado con "?" de un desafío.
func has_challenge_mark(tile: int) -> bool:
	return _challenge_marks.has(tile)


## Verdadero si la casilla lleva el icono de una casilla especial (recompensa u obstáculo).
func has_special_mark(tile: int) -> bool:
	return _special_marks.has(tile)


## Centro de la cara superior de una casilla, en el espacio del tablero.
func tile_position(tile: int) -> Vector3:
	return layout.tile_center(tile)


## Camino que recorre una ficha al subir por una escalera (de la casilla de abajo a la de arriba).
func ladder_path(from_tile: int, to_tile: int) -> PackedVector3Array:
	var lift := Vector3(0.0, LADDER_LIFT, 0.0)
	return PackedVector3Array([layout.tile_center(from_tile) + lift, layout.tile_center(to_tile) + lift])


## Peldaños de una escalera (también sirve para saber cuántos saltitos da la ficha al subir).
func ladder_rungs(from_tile: int, to_tile: int) -> int:
	var length: float = layout.tile_center(from_tile).distance_to(layout.tile_center(to_tile))
	return maxi(2, int(length / 0.42))


## Camino de una ficha que resbala por una serpiente: sigue el lomo de la serpiente
## desde la cabeza hasta la cola, el mismo que se dibuja en el tablero.
func snake_path(head_tile: int, tail_tile: int) -> PackedVector3Array:
	var geometry: Dictionary = _snake_geometry(head_tile, tail_tile)
	var points: PackedVector3Array = geometry["points"]
	var radii: PackedFloat32Array = geometry["radii"]
	var path := PackedVector3Array()
	for i in points.size():
		path.append(Vector3(points[i].x, BoardLayout.TILE_HEIGHT + radii[i] * 2.0, points[i].z))
	return path


## Nodo de la cabeza de la serpiente que empieza en esa casilla (para animar su mordisco).
func snake_head_node(head_tile: int) -> Node3D:
	if _snakes_root == null:
		return null
	var tail_tile: int = layout.jump_target(head_tile)
	return _snakes_root.get_node_or_null("Snake_%03d_%03d/Head" % [head_tile, tail_tile]) as Node3D


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
	var frame_color: Color = _color("frame", Color(0.42, 0.27, 0.15))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x + BoardLayout.FRAME_MARGIN * 2.0, BoardLayout.FRAME_THICKNESS,
			size.y + BoardLayout.FRAME_MARGIN * 2.0)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = mesh
	frame.material_override = _material("frame", frame_color, 0.9)
	frame.position = Vector3(0.0, -BoardLayout.FRAME_THICKNESS * 0.5, 0.0)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)

	# Decoración propia del estilo sobre el marco (seto, borda, muro, cerca...).
	var decor := MeshKit.new()
	var glow := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("marco:" + layout.map_id)
	BoardStyle.add_frame_decor(decor, glow, _style, size, rng, frame_color)
	if not decor.is_empty():
		add_child(decor.instance(TextureKit.plain(0.85), "FrameDecor"))
	if not glow.is_empty():
		add_child(glow.instance(TextureKit.glow_vertex(true), "FrameGlow"))


## Las casillas: un ancla por casilla ("Tile_001"...) y tres mallas para todo el tablero: la
## superficie con su textura, las figuras de las marcas y los números (sin luz).
func _build_tiles() -> void:
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("casillas:" + layout.map_id)
	var surface := MeshKit.new()
	surface.uv_scale = BoardStyle.texture_scale(_style)
	var marks := MeshKit.new()
	var ink := MeshKit.new()
	var color_a: Color = _color("tile_a", Color(0.92, 0.82, 0.60))
	var color_b: Color = _color("tile_b", Color(0.84, 0.65, 0.40))

	for tile in range(1, layout.tile_count() + 1):
		var cell: Vector2i = layout.grid_of(tile)
		var base: Color = color_a if (cell.x + cell.y) % 2 == 0 else color_b
		var color: Color = _tile_color(tile, base)
		var center: Vector3 = layout.tile_center(tile)

		var anchor := Node3D.new()
		anchor.name = "Tile_%03d" % tile
		anchor.position = center
		anchor.set_meta(&"tile", tile)
		_tiles_root.add_child(anchor)

		BoardStyle.add_tile(surface, _style, center, color, rng)
		TileMarks.add_number(ink, tile, center, color)
		if layout.is_challenge_tile(tile):
			TileMarks.add_challenge(marks, ink, center)
			_challenge_marks[tile] = true
		var special: Dictionary = layout.special_at(tile)
		if not special.is_empty():
			TileMarks.add_special(marks, ink, str(special.get("kind", "")), center)
			_special_marks[tile] = true

	add_child(surface.instance(TextureKit.material(BoardStyle.texture_kind(_style), 0.88), "TileSurface"))
	add_child(marks.instance(TextureKit.plain(0.45), "TileMarks"))
	add_child(ink.instance(_ink_material(), "TileInk"))


## Material de los números: sin luz, para que se lean igual de día que de noche.
func _ink_material() -> StandardMaterial3D:
	if not _materials.has("ink"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		_materials["ink"] = m
	return _materials["ink"]


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
		"challenge":
			return base.lerp(CHALLENGE_TINT, 0.38)
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
	if layout.is_challenge_tile(tile):
		return "challenge"
	return ""


# ---------------------------------------------------------------- Escaleras

func _build_ladders() -> void:
	_ladders_root = Node3D.new()
	_ladders_root.name = "Ladders"
	add_child(_ladders_root)

	var tones: Array[Color] = BoardStyle.ladder_colors(_style)
	var material: StandardMaterial3D = TextureKit.plain(0.8)
	for pair in layout.ladders:
		var from_pos: Vector3 = layout.tile_center(pair.x)
		var to_pos: Vector3 = layout.tile_center(pair.y)
		var delta: Vector3 = to_pos - from_pos
		var length: float = delta.length()
		var middle: Vector3 = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.07, 0.0)

		var ladder := Node3D.new()
		ladder.name = "Ladder_%03d_%03d" % [pair.x, pair.y]
		_ladders_root.add_child(ladder)

		# Larguero y peldaños en una sola malla, con los colores del estilo.
		var kit := MeshKit.new()
		kit.push_xf(Transform3D(Basis.looking_at(delta / length, Vector3.UP), middle))
		for side in [-1.0, 1.0]:
			kit.box(Vector3(float(side) * LADDER_WIDTH * 0.5, 0.0, 0.0), Vector3(0.07, 0.09, length), tones[0])
		var rung_count: int = maxi(2, int(length / 0.42))
		for i in rung_count:
			var t: float = (float(i) + 0.5) / float(rung_count)
			kit.box(Vector3(0.0, 0.0, -length * 0.5 + t * length), Vector3(LADDER_WIDTH + 0.08, 0.05, 0.07), tones[1])
		kit.pop()
		var body: MeshInstance3D = kit.instance(material, "Body")
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		ladder.add_child(body)


# ---------------------------------------------------------------- Serpientes

func _build_snakes() -> void:
	_snakes_root = Node3D.new()
	_snakes_root.name = "Snakes"
	add_child(_snakes_root)
	var palette: Array[Color] = BoardStyle.snake_colors(_style)
	var index: int = 0
	for pair in layout.snakes:
		var color: Color = palette[index % palette.size()]
		_snakes_root.add_child(_make_snake(pair.x, pair.y, color))
		index += 1


## Una serpiente: cuerpo ondulado (tubo) desde la cabeza, en la casilla alta,
## hasta la cola, en la casilla baja, más cabeza, ojos y lengua.
func _make_snake(head_tile: int, tail_tile: int, color: Color) -> Node3D:
	var head_pos: Vector3 = layout.tile_center(head_tile)
	var geometry: Dictionary = _snake_geometry(head_tile, tail_tile)
	var points: PackedVector3Array = geometry["points"]
	var radii: PackedFloat32Array = geometry["radii"]
	var colors := PackedColorArray()
	for i in points.size():
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


## Línea central ondulada del cuerpo de una serpiente (cabeza -> cola) y el radio en cada punto.
func _snake_geometry(head_tile: int, tail_tile: int) -> Dictionary:
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
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var along: Vector3 = head_pos.lerp(tail_pos, t)
		var wiggle: float = sin(t * TAU * waves) * 0.34 * sin(t * PI)
		var radius: float = 0.13 * lerpf(1.0, 0.2, pow(t, 1.4))
		points.append(Vector3(along.x, BoardLayout.TILE_HEIGHT + radius, along.z) + side * wiggle)
		radii.append(radius)
	return {"points": points, "radii": radii}


## La cabeza (cráneo, ojos pupilas y lengua) en una sola malla. Mira hacia -Z.
func _add_snake_head_parts(head: Node3D, color: Color) -> void:
	var kit := MeshKit.new()
	kit.sphere(Vector3(0.0, 0.17, -0.05), Vector3(0.19, 0.152, 0.2375), color.lightened(0.08), 10, 6)
	var white := Color(0.98, 0.98, 0.94)
	var black := Color(0.05, 0.04, 0.04)
	var red := Color(0.88, 0.12, 0.18)
	for side in [-1.0, 1.0]:
		var s: float = float(side)
		kit.sphere(Vector3(s * 0.11, 0.28, -0.12), Vector3(0.06, 0.06, 0.06), white, 7, 4)
		kit.sphere(Vector3(s * 0.11, 0.29, -0.17), Vector3(0.032, 0.032, 0.032), black, 5, 3)
	kit.box(Vector3(0.0, 0.1, -0.4), Vector3(0.035, 0.012, 0.26), red)
	for side in [-1.0, 1.0]:
		var s: float = float(side)
		kit.place(Vector3(s * 0.04, 0.1, -0.56), s * 0.45)
		kit.box(Vector3.ZERO, Vector3(0.03, 0.012, 0.12), red)
		kit.pop()
	var skin: MeshInstance3D = kit.instance(TextureKit.plain(0.5), "HeadMesh")
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	head.add_child(skin)


# ---------------------------------------------------------------- Inicio, meta y dado

## Puerta de salida, a la izquierda de la casilla 1, con el aspecto del escenario del mapa.
func _build_start_marker() -> void:
	var start: Vector3 = layout.tile_center(1)
	var root := Node3D.new()
	root.name = "StartMarker"
	root.position = Vector3(start.x - (BoardLayout.TILE_SIZE * 0.5 + 0.2), 0.0, start.z + 0.1)
	add_child(root)

	var kit := MeshKit.new()
	var glow := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("salida:" + layout.map_id)
	var label_y: float = BoardLandmarks.add_start(kit, glow, _style, rng, START_COLOR)
	root.add_child(kit.instance(TextureKit.plain(0.7), "Body"))
	if not glow.is_empty():
		root.add_child(glow.instance(TextureKit.glow_vertex(true), "Glow"))
	root.add_child(_make_billboard("INICIO", Vector3(0.0, label_y, 0.0), Color(0.80, 1.0, 0.82)))


## Puerta de llegada, sobre la casilla de meta, con el aspecto del escenario del mapa.
func _build_goal_marker() -> void:
	var goal: Vector3 = layout.tile_center(layout.tile_count())
	var root := Node3D.new()
	root.name = "GoalMarker"
	root.position = goal
	add_child(root)

	var kit := MeshKit.new()
	var glow := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("meta:" + layout.map_id)
	var label_y: float = BoardLandmarks.add_goal(kit, glow, _style, rng, GOAL_COLOR)
	root.add_child(kit.instance(TextureKit.plain(0.45), "Body"))
	if not glow.is_empty():
		root.add_child(glow.instance(TextureKit.glow_vertex(true), "Glow"))
	root.add_child(_make_billboard("META", Vector3(0.0, label_y, 0.0), Color(1.0, 0.92, 0.6)))


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
