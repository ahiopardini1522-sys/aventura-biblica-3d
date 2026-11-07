class_name EnvFactory
extends RefCounted
## Crea el entorno (cielo, luz ambiente, niebla) de una escena 3D.
## Se hace por código para poder cambiar los colores según el mapa elegido.


static func create(sky_top: Color, sky_horizon: Color, ground: Color, ambient: Color,
		fog: Color, fog_density: float, ambient_energy: float = 1.0) -> Environment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = sky_horizon
	sky_material.ground_horizon_color = sky_horizon
	sky_material.ground_bottom_color = ground
	sky_material.sky_curve = 0.2
	sky_material.sun_angle_max = 35.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = fog
	env.fog_density = fog_density
	return env
