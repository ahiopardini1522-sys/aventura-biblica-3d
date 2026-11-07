class_name PropFactory
extends RefCounted
## Elementos decorativos low poly hechos por código: palmeras, rocas, dunas y nubes.

static var _materials: Dictionary = {}


static func _mat(key: String, color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	if not _materials.has(key):
		_materials[key] = MeshFactory.material(color, roughness)
	return _materials[key]


static func palm(rng: RandomNumberGenerator, height: float = 3.6) -> Node3D:
	var root := Node3D.new()
	root.name = "Palm"
	var segments: int = 3
	var seg_h: float = height / float(segments)
	var trunk_mat: StandardMaterial3D = _mat("trunk", Color(0.42, 0.29, 0.17))
	var lean_x: float = rng.randf_range(-0.14, 0.14)
	var lean_z: float = rng.randf_range(-0.10, 0.10)
	var top := Vector3.ZERO
	for i in segments:
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = 0.21 - 0.04 * float(i)
		mesh.top_radius = 0.21 - 0.04 * float(i + 1)
		mesh.height = seg_h
		mesh.radial_segments = 6
		mesh.rings = 1
		var seg := MeshInstance3D.new()
		seg.mesh = mesh
		seg.material_override = trunk_mat
		seg.position = top + Vector3(0.0, seg_h * 0.5, 0.0)
		root.add_child(seg)
		top += Vector3(lean_x, seg_h, lean_z)

	var crown := Node3D.new()
	crown.name = "Crown"
	crown.position = top
	root.add_child(crown)

	var frond_mesh := BoxMesh.new()
	frond_mesh.size = Vector3(0.36, 0.04, 1.9)
	var frond_mats: Array = [
		_mat("frond_a", Color(0.24, 0.52, 0.20)),
		_mat("frond_b", Color(0.31, 0.61, 0.25)),
	]
	var fronds: int = 8
	for i in fronds:
		var pivot := Node3D.new()
		pivot.rotation = Vector3(deg_to_rad(rng.randf_range(20.0, 34.0)),
				TAU * float(i) / float(fronds) + rng.randf_range(-0.2, 0.2), 0.0)
		crown.add_child(pivot)
		var frond := MeshInstance3D.new()
		frond.mesh = frond_mesh
		frond.material_override = frond_mats[i % 2]
		frond.position = Vector3(0.0, 0.0, 0.95)
		pivot.add_child(frond)

	var nut_mesh := SphereMesh.new()
	nut_mesh.radius = 0.12
	nut_mesh.height = 0.24
	nut_mesh.radial_segments = 8
	nut_mesh.rings = 4
	for offset in [Vector3(0.14, -0.1, 0.1), Vector3(-0.12, -0.12, 0.08)]:
		var nut := MeshInstance3D.new()
		nut.mesh = nut_mesh
		nut.material_override = _mat("nut", Color(0.32, 0.2, 0.1))
		nut.position = offset
		crown.add_child(nut)
	return root


static func rock(rng: RandomNumberGenerator) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.name = "Rock"
	instance.mesh = mesh
	var shade: float = rng.randf_range(0.0, 1.0)
	instance.material_override = _mat("rock_%d" % int(shade * 3.0), Color(0.5, 0.42, 0.36).lerp(Color(0.68, 0.58, 0.48), shade))
	instance.scale = Vector3(rng.randf_range(0.5, 1.5), rng.randf_range(0.35, 0.8), rng.randf_range(0.5, 1.3))
	instance.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
	return instance


static func dune(rng: RandomNumberGenerator, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.name = "Dune"
	instance.mesh = mesh
	instance.material_override = _mat("dune_%s" % color.to_html(false), color.lightened(rng.randf_range(0.0, 0.12)), 1.0)
	instance.scale = Vector3(rng.randf_range(5.0, 10.0), rng.randf_range(0.9, 1.8), rng.randf_range(4.0, 8.0))
	instance.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
	return instance


static func cloud(rng: RandomNumberGenerator) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 5
	var instance := MeshInstance3D.new()
	instance.name = "Cloud"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.97, 0.92, rng.randf_range(0.55, 0.85))
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.scale = Vector3(rng.randf_range(9.0, 16.0), rng.randf_range(1.2, 2.2), rng.randf_range(3.0, 5.5))
	return instance
