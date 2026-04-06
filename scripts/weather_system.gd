extends Node3D

## Weather system that creates rain/snow particle effects attached to the camera.
## Also adjusts environment (sky, fog, light) to match the weather.

enum WeatherType { CLEAR, RAIN, SNOW }

@export var current_weather: WeatherType = WeatherType.CLEAR

var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D

# Store original environment values for restoring on CLEAR
var _orig_sky_top: Color
var _orig_sky_horizon: Color
var _orig_fog_color: Color
var _orig_fog_density: float
var _orig_sun_color: Color
var _orig_sun_energy: float
var _orig_glow_intensity: float


func _ready() -> void:
	# Find environment and sun in the scene
	var world_env := _find_typed_in_tree(get_tree().root, &"WorldEnvironment")
	if world_env:
		_env = (world_env as WorldEnvironment).environment
	_sun = _find_typed_in_tree(get_tree().root, &"DirectionalLight3D") as DirectionalLight3D

	# Save original values
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			_orig_sky_top = sky_mat.sky_top_color
			_orig_sky_horizon = sky_mat.sky_horizon_color
		_orig_fog_color = _env.fog_light_color
		_orig_fog_density = _env.fog_density
		_orig_glow_intensity = _env.glow_intensity
	if _sun:
		_orig_sun_color = _sun.light_color
		_orig_sun_energy = _sun.light_energy

	# Create particle systems (initially hidden)
	_rain_particles = _create_rain_particles()
	add_child(_rain_particles)
	_rain_particles.emitting = false

	_snow_particles = _create_snow_particles()
	add_child(_snow_particles)
	_snow_particles.emitting = false


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
			sky_mat.sky_top_color = _orig_sky_top
			sky_mat.sky_horizon_color = _orig_sky_horizon
		_env.fog_light_color = _orig_fog_color
		_env.fog_density = _orig_fog_density
		_env.glow_intensity = _orig_glow_intensity
	if _sun:
		_sun.light_color = _orig_sun_color
		_sun.light_energy = _orig_sun_energy


func _apply_rain() -> void:
	_rain_particles.emitting = true
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = Color(0.2, 0.22, 0.3, 1)
			sky_mat.sky_horizon_color = Color(0.4, 0.42, 0.48, 1)
		_env.fog_light_color = Color(0.45, 0.48, 0.55, 1)
		_env.fog_density = 0.005
		_env.glow_intensity = 0.2
	if _sun:
		_sun.light_color = Color(0.5, 0.55, 0.65, 1)
		_sun.light_energy = 0.4


func _apply_snow() -> void:
	_snow_particles.emitting = true
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = Color(0.6, 0.65, 0.75, 1)
			sky_mat.sky_horizon_color = Color(0.8, 0.82, 0.88, 1)
		_env.fog_light_color = Color(0.8, 0.82, 0.88, 1)
		_env.fog_density = 0.008
		_env.glow_intensity = 0.6
	if _sun:
		_sun.light_color = Color(0.75, 0.78, 0.85, 1)
		_sun.light_energy = 0.5


func _process(_delta: float) -> void:
	# Follow the camera so particles always surround the player
	_camera = get_viewport().get_camera_3d()
	if _camera:
		global_position = _camera.global_position


func _create_rain_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "RainParticles"
	particles.amount = 3000
	particles.lifetime = 1.2
	particles.speed_scale = 1.5
	particles.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 5.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 20.0
	mat.gravity = Vector3(0, -15, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 0.5, 25)
	mat.scale_min = 0.03
	mat.scale_max = 0.05
	mat.color = Color(0.7, 0.75, 0.85, 0.4)
	particles.process_material = mat

	# Use a simple stretched mesh for raindrops
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.6, 0.02)
	particles.draw_pass_1 = mesh

	# Offset up so rain falls from above
	particles.position = Vector3(0, 12, 0)
	return particles


func _create_snow_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SnowParticles"
	particles.amount = 2000
	particles.lifetime = 4.0
	particles.speed_scale = 1.0
	particles.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -2, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 0.5, 25)
	mat.scale_min = 0.08
	mat.scale_max = 0.15
	mat.color = Color(0.95, 0.95, 1.0, 0.8)
	# Add slight turbulence for drifting effect
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.0
	mat.turbulence_noise_scale = 1.5
	mat.turbulence_noise_speed_random = 0.5
	particles.process_material = mat

	# Snowflakes as small spheres
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	particles.draw_pass_1 = mesh

	# Offset up so snow falls from above
	particles.position = Vector3(0, 12, 0)
	return particles


func _find_typed_in_tree(root: Node, type_name: StringName) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed_in_tree(child, type_name)
		if found:
			return found
	return null
