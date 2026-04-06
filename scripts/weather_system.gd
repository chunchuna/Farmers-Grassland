extends Node3D

## Weather system using CPUParticles3D (compatible with GL Compatibility renderer).
## All weather parameters are exported — select the WeatherSystem node in the
## scene tree and tweak values in the Inspector.

enum WeatherType { CLEAR, RAIN, SNOW }

@export var current_weather: WeatherType = WeatherType.CLEAR

## ─── CLEAR weather settings ───
@export_group("Clear Weather")
@export var clear_sky_top := Color(0.35, 0.55, 0.85, 1)
@export var clear_sky_horizon := Color(0.7, 0.8, 0.9, 1)
@export var clear_fog_color := Color(0.75, 0.82, 0.7, 1)
@export var clear_fog_density := 0.001
@export var clear_sun_color := Color(1, 0.95, 0.85, 1)
@export var clear_sun_energy := 0.7
@export var clear_glow_intensity := 0.4

## ─── RAIN weather settings ───
@export_group("Rain Weather")
@export var rain_sky_top := Color(0.2, 0.22, 0.3, 1)
@export var rain_sky_horizon := Color(0.4, 0.42, 0.48, 1)
@export var rain_fog_color := Color(0.45, 0.48, 0.55, 1)
@export var rain_fog_density := 0.005
@export var rain_sun_color := Color(0.5, 0.55, 0.65, 1)
@export var rain_sun_energy := 0.3
@export var rain_glow_intensity := 0.2
@export var rain_particle_count := 3000
@export var rain_particle_color := Color(0.7, 0.75, 0.85, 0.5)

## ─── SNOW weather settings ───
@export_group("Snow Weather")
@export var snow_sky_top := Color(0.6, 0.65, 0.75, 1)
@export var snow_sky_horizon := Color(0.8, 0.82, 0.88, 1)
@export var snow_fog_color := Color(0.8, 0.82, 0.88, 1)
@export var snow_fog_density := 0.008
@export var snow_sun_color := Color(0.75, 0.78, 0.85, 1)
@export var snow_sun_energy := 0.4
@export var snow_glow_intensity := 0.6
@export var snow_particle_count := 2000
@export var snow_particle_color := Color(0.95, 0.95, 1.0, 0.85)

var _rain_particles: CPUParticles3D
var _snow_particles: CPUParticles3D
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	# Find environment and sun in the scene
	var world_env := _find_typed_in_tree(get_tree().root, &"WorldEnvironment")
	if world_env:
		_env = (world_env as WorldEnvironment).environment
	_sun = _find_typed_in_tree(get_tree().root, &"DirectionalLight3D") as DirectionalLight3D

	# Create CPU particle systems (GL Compatibility compatible)
	_rain_particles = _create_rain_particles()
	add_child(_rain_particles)
	_rain_particles.emitting = false

	_snow_particles = _create_snow_particles()
	add_child(_snow_particles)
	_snow_particles.emitting = false

	# Apply initial weather
	set_weather(current_weather)


func set_weather(weather: WeatherType) -> void:
	current_weather = weather
	_rain_particles.emitting = false
	_snow_particles.emitting = false

	match weather:
		WeatherType.CLEAR:
			_apply_clear()
		WeatherType.RAIN:
			_apply_rain()
		WeatherType.SNOW:
			_apply_snow()

	print("Weather changed to: %s" % WeatherType.keys()[weather])


func _apply_clear() -> void:
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = clear_sky_top
			sky_mat.sky_horizon_color = clear_sky_horizon
		_env.fog_light_color = clear_fog_color
		_env.fog_density = clear_fog_density
		_env.glow_intensity = clear_glow_intensity
	if _sun:
		_sun.light_color = clear_sun_color
		_sun.light_energy = clear_sun_energy


func _apply_rain() -> void:
	_rain_particles.emitting = true
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = rain_sky_top
			sky_mat.sky_horizon_color = rain_sky_horizon
		_env.fog_light_color = rain_fog_color
		_env.fog_density = rain_fog_density
		_env.glow_intensity = rain_glow_intensity
	if _sun:
		_sun.light_color = rain_sun_color
		_sun.light_energy = rain_sun_energy


func _apply_snow() -> void:
	_snow_particles.emitting = true
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = snow_sky_top
			sky_mat.sky_horizon_color = snow_sky_horizon
		_env.fog_light_color = snow_fog_color
		_env.fog_density = snow_fog_density
		_env.glow_intensity = snow_glow_intensity
	if _sun:
		_sun.light_color = snow_sun_color
		_sun.light_energy = snow_sun_energy


func _process(_delta: float) -> void:
	# Follow the camera so particles always surround the player
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position


func _create_rain_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "RainParticles"
	p.amount = rain_particle_count
	p.lifetime = 1.5
	p.speed_scale = 1.5
	p.randomness = 0.1

	# Emission: box above player
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 0.5, 20)

	# Movement
	p.direction = Vector3(0, -1, 0)
	p.spread = 5.0
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 25.0
	p.gravity = Vector3(0, -12, 0)

	# Appearance
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.025
	p.color = rain_particle_color

	# Raindrop mesh: thin tall box
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.8, 0.03)
	p.mesh = mesh

	# Position above camera
	p.position = Vector3(0, 15, 0)
	return p


func _create_snow_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SnowParticles"
	p.amount = snow_particle_count
	p.lifetime = 5.0
	p.speed_scale = 1.0
	p.randomness = 0.3

	# Emission: box above player
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 0.5, 20)

	# Movement — slow drift
	p.direction = Vector3(0, -1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0.3, -1.5, 0.2)

	# Appearance
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.1
	p.color = snow_particle_color

	# Snowflake mesh: small sphere
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh

	# Position above camera
	p.position = Vector3(0, 15, 0)
	return p


func _find_typed_in_tree(root: Node, type_name: StringName) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed_in_tree(child, type_name)
		if found:
			return found
	return null
