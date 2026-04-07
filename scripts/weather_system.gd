extends Node3D

## Weather system using CPUParticles3D (compatible with GL Compatibility renderer).
## All weather parameters are exported — select the WeatherSystem node in the
## scene tree and tweak values in the Inspector.
## Weather is synced across multiplayer via RPC.

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
@export var rain_particle_count := 4000
@export var rain_particle_color := Color(0.6, 0.65, 0.8, 0.6)

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
@export var snow_particle_color := Color(0.9, 0.92, 1.0, 0.9)

var _rain_particles: CPUParticles3D
var _snow_particles: CPUParticles3D
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	# Find environment and sun in the scene
	var world_env := _find_typed_in_tree(get_tree().root, &"WorldEnvironment")
	if world_env:
		_env = (world_env as WorldEnvironment).environment
		print("WeatherSystem: Found WorldEnvironment")
	else:
		push_warning("WeatherSystem: WorldEnvironment not found!")

	_sun = _find_typed_in_tree(get_tree().root, &"DirectionalLight3D") as DirectionalLight3D
	if _sun:
		print("WeatherSystem: Found DirectionalLight3D")
		# Make sure sun is visible
		_sun.visible = true

	# Create CPU particle systems (GL Compatibility compatible)
	# Set emitting=false BEFORE adding to tree to prevent initial burst
	_rain_particles = _create_rain_particles()
	_rain_particles.emitting = false
	_rain_particles.visible = false
	add_child(_rain_particles)

	_snow_particles = _create_snow_particles()
	_snow_particles.emitting = false
	_snow_particles.visible = false
	add_child(_snow_particles)

	print("WeatherSystem: Ready (rain=%d particles, snow=%d particles)" % [_rain_particles.amount, _snow_particles.amount])

	# Apply initial weather
	_apply_weather_local(current_weather)


## Call this from the debug panel. Handles multiplayer sync automatically.
func set_weather(weather: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client: ask server to change weather
		_rpc_request_weather.rpc_id(1, weather)
	else:
		# Server or single-player: apply directly and broadcast
		_apply_weather_local(weather)
		if multiplayer.has_multiplayer_peer():
			_rpc_sync_weather.rpc(weather)


## Apply weather locally (no network).
func _apply_weather_local(weather: int) -> void:
	current_weather = weather as WeatherType
	# Stop and hide both particle systems, restart to clear any stale particles
	_rain_particles.emitting = false
	_rain_particles.visible = false
	_rain_particles.restart()
	_snow_particles.emitting = false
	_snow_particles.visible = false
	_snow_particles.restart()

	match current_weather:
		WeatherType.CLEAR:
			_apply_clear()
		WeatherType.RAIN:
			_apply_rain()
		WeatherType.SNOW:
			_apply_snow()

	print("WeatherSystem: Weather set to %s" % WeatherType.keys()[current_weather])


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
		_sun.visible = true
		_sun.light_color = clear_sun_color
		_sun.light_energy = clear_sun_energy


func _apply_rain() -> void:
	_rain_particles.visible = true
	_rain_particles.restart()
	_rain_particles.emitting = true
	print("WeatherSystem: Rain particles emitting=%s, amount=%d, pos=%s" % [_rain_particles.emitting, _rain_particles.amount, _rain_particles.global_position])
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = rain_sky_top
			sky_mat.sky_horizon_color = rain_sky_horizon
		_env.fog_light_color = rain_fog_color
		_env.fog_density = rain_fog_density
		_env.glow_intensity = rain_glow_intensity
	if _sun:
		_sun.visible = true
		_sun.light_color = rain_sun_color
		_sun.light_energy = rain_sun_energy


func _apply_snow() -> void:
	_snow_particles.visible = true
	_snow_particles.restart()
	_snow_particles.emitting = true
	print("WeatherSystem: Snow particles emitting=%s, amount=%d, pos=%s" % [_snow_particles.emitting, _snow_particles.amount, _snow_particles.global_position])
	if _env:
		var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat:
			sky_mat.sky_top_color = snow_sky_top
			sky_mat.sky_horizon_color = snow_sky_horizon
		_env.fog_light_color = snow_fog_color
		_env.fog_density = snow_fog_density
		_env.glow_intensity = snow_glow_intensity
	if _sun:
		_sun.visible = true
		_sun.light_color = snow_sun_color
		_sun.light_energy = snow_sun_energy


func _process(_delta: float) -> void:
	# Follow the camera so particles always surround the player
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position


# ─── Particle creation ───

func _create_rain_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "RainParticles"
	p.amount = rain_particle_count
	p.lifetime = 1.8
	p.speed_scale = 1.5
	p.randomness = 0.1
	p.fixed_fps = 60

	# Emission: large box above player
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 1, 20)

	# Movement
	p.direction = Vector3(0, -1, 0)
	p.spread = 3.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 30.0
	p.gravity = Vector3(0, -15, 0)

	# Scale — use larger values so particles are clearly visible
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0

	# Color
	p.color = rain_particle_color

	# Raindrop mesh with material
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.5, 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rain_particle_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh

	# Position above camera
	p.position = Vector3(0, 15, 0)
	return p


func _create_snow_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SnowParticles"
	p.amount = snow_particle_count
	p.lifetime = 6.0
	p.speed_scale = 1.0
	p.randomness = 0.4
	p.fixed_fps = 30

	# Emission: large box above player
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 1, 20)

	# Movement — slow drift
	p.direction = Vector3(0, -1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0.3, -1.2, 0.2)

	# Scale
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.5

	# Color
	p.color = snow_particle_color

	# Snowflake mesh with material
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = snow_particle_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh

	# Position above camera
	p.position = Vector3(0, 15, 0)
	return p


# ─── Multiplayer RPCs ───

## Client → Server: request weather change
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_weather(weather: int) -> void:
	if multiplayer.is_server():
		_apply_weather_local(weather)
		_rpc_sync_weather.rpc(weather)


## Server → All Clients: sync weather state
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_weather(weather: int) -> void:
	_apply_weather_local(weather)


## Called by game_manager when a new peer joins — send current weather to that peer only.
func send_weather_to(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_sync_weather.rpc_id(peer_id, current_weather as int)


# ─── Utility ───

func _find_typed_in_tree(root: Node, type_name: StringName) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed_in_tree(child, type_name)
		if found:
			return found
	return null
