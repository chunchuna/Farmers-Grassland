extends CharacterBody3D

## Movement speed (m/s)
@export var walk_speed: float = 6.0
## Sprint speed (m/s)
@export var sprint_speed: float = 10.0
## Jump impulse (m/s)
@export var jump_velocity: float = 6.0
## Mouse sensitivity
@export var mouse_sensitivity: float = 0.002
## Gravity multiplier
@export var gravity_multiplier: float = 1.5

@export_group("Third Person Camera")
## Default camera mode on start (true = third person)
@export var start_in_third_person: bool = false
## Distance from the player (SpringArm length)
@export_range(1.0, 20.0, 0.5) var tp_distance: float = 4.0
## Vertical offset of the pivot point above player origin
@export_range(0.5, 3.0, 0.1) var tp_height: float = 1.4
## Vertical angle offset in degrees (positive = look down)
@export_range(-30.0, 60.0, 1.0) var tp_pitch_offset: float = 10.0
## Horizontal offset (positive = right)
@export_range(-2.0, 2.0, 0.1) var tp_horizontal_offset: float = 0.5
## Camera FOV in third-person mode
@export_range(50.0, 120.0, 1.0) var tp_fov: float = 75.0
## Camera FOV in first-person mode
@export_range(50.0, 120.0, 1.0) var fp_fov: float = 75.0
## SpringArm collision margin
@export_range(0.05, 1.0, 0.05) var tp_collision_margin: float = 0.2

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var player_model: Node3D = $PlayerModel
@onready var _tp_pivot: Node3D = $ThirdPersonPivot
@onready var _spring_arm: SpringArm3D = $ThirdPersonPivot/SpringArm3D
@onready var _tp_camera: Camera3D = $ThirdPersonPivot/SpringArm3D/TPCamera

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_settled: bool = false
var _settle_frames: int = 0
var _settle_time: float = 0.0
var _is_third_person: bool = false


func _ready() -> void:
	add_to_group("players")
	# Determine if this is the local player
	var is_local := _is_local_player()

	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Apply third-person config to scene nodes
		_apply_tp_config()
		# Set initial camera mode
		if start_in_third_person:
			_set_third_person(true)
		else:
			_set_third_person(false)
		# Enable SimpleGrassTextured interactive mode
		var sgt := get_node_or_null("/root/SimpleGrass")
		if sgt:
			sgt.set_interactive(true)
		# Create invisible proxy mesh on layer 17 for grass interaction
		_create_grass_proxy()
	else:
		# Remote player — disable input/camera, show model
		camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)
		player_model.visible = true
		# Set visual layer 17 so grass reacts to remote players
		_set_visual_layer_17(player_model)
		return

	# Start settling: freeze movement until we land on terrain
	_spawn_settled = false
	_settle_frames = 0


func _create_grass_proxy() -> void:
	var proxy := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	proxy.mesh = sphere
	# Only on layer 17 (bit 16) — SGT's camera sees it, main camera won't
	proxy.layers = 1 << 16
	proxy.name = "GrassProxy"
	add_child(proxy)
	proxy.position = Vector3(0, 0.5, 0)
	# Exclude layer 17 from both cameras so proxy is invisible to player
	if camera:
		camera.cull_mask = camera.cull_mask & ~(1 << 16)
	if _tp_camera:
		_tp_camera.cull_mask = _tp_camera.cull_mask & ~(1 << 16)


func _set_visual_layer_17(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = node.layers | (1 << 16)  # Layer 17 is bit 16 (0-indexed)
	for child in node.get_children():
		_set_visual_layer_17(child)


func _is_local_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true  # Single player
	return get_multiplayer_authority() == multiplayer.get_unique_id()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Horizontal rotation on the body
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Vertical rotation on the head/camera
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		# Sync third-person pivot with head vertical look
		if _is_third_person and _tp_pivot:
			_tp_pivot.rotation.x = head.rotation.x

	if event is InputEventKey and event.pressed and event.keycode == KEY_V and not event.echo:
		_set_third_person(not _is_third_person)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Safety net: if we fell way below the terrain, teleport back up
	if global_position.y < -50.0:
		print("Player: Fell below terrain, resetting position")
		global_position = Vector3(0, 50, 0)
		velocity = Vector3.ZERO
		_spawn_settled = false
		_settle_frames = 0
		return

	# Settling phase: just apply gravity until we land
	if not _spawn_settled:
		velocity.y -= _gravity * gravity_multiplier * delta
		move_and_slide()
		_settle_frames += 1
		_settle_time += delta
		if is_on_floor() and _settle_frames > 3:
			_spawn_settled = true
			velocity = Vector3.ZERO
			print("Player: Settled on terrain at Y=%.2f" % global_position.y)
		elif _settle_time > 5.0:
			# Timeout: no collision found, settle at Y=0
			_spawn_settled = true
			global_position.y = 1.0
			velocity = Vector3.ZERO
			print("Player: Settle timeout, placing at Y=1.0")
		return

	# Normal gameplay
	# Gravity
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta

	# Jump
	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	# Movement direction
	var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	var input_dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 5.0 * delta)

	move_and_slide()

	# Drive walker animation blend based on horizontal speed
	_update_animation()

	# Update SimpleGrassTextured player position for interactive grass
	var sgt := get_node_or_null("/root/SimpleGrass")
	if sgt:
		sgt.set_player_position(global_position)


func _apply_tp_config() -> void:
	if _tp_pivot:
		_tp_pivot.position.y = tp_height
	if _spring_arm:
		_spring_arm.spring_length = tp_distance
		_spring_arm.margin = tp_collision_margin
	if _tp_camera:
		_tp_camera.position.x = tp_horizontal_offset
		_tp_camera.fov = tp_fov
	if camera:
		camera.fov = fp_fov


func _set_third_person(enabled: bool) -> void:
	_is_third_person = enabled
	if _is_third_person:
		# Third-person: show model, use TP camera
		player_model.visible = true
		_tp_camera.make_current()
		_tp_pivot.visible = true
		# Apply pitch offset
		_spring_arm.rotation.x = deg_to_rad(-tp_pitch_offset)
	else:
		# First-person: hide model, use FP camera
		player_model.visible = false
		camera.make_current()
		_tp_pivot.visible = false


func _update_animation() -> void:
	if not player_model or not player_model.has_method("set_movement_blend"):
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	# Map speed to blend: 0 = idle, walk_speed = 0.5, sprint_speed = 1.0
	var blend: float
	if horizontal_speed < 0.1:
		blend = 0.0
	elif horizontal_speed <= walk_speed:
		blend = remap(horizontal_speed, 0.0, walk_speed, 0.0, 0.5)
	else:
		blend = remap(horizontal_speed, walk_speed, sprint_speed, 0.5, 1.0)
	player_model.set_movement_blend(blend)
