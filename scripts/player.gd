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

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var player_model: Node3D = $PlayerModel

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_settled: bool = false
var _settle_frames: int = 0


func _ready() -> void:
	add_to_group("players")
	# Determine if this is the local player
	var is_local := _is_local_player()

	if is_local:
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Hide own model for first-person view
		player_model.visible = false
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
	# Exclude layer 17 from main camera so proxy is invisible to player
	if camera:
		camera.cull_mask = camera.cull_mask & ~(1 << 16)


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
		if is_on_floor() and _settle_frames > 3:
			_spawn_settled = true
			velocity = Vector3.ZERO
			print("Player: Settled on terrain at Y=%.2f" % global_position.y)
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

	# Update SimpleGrassTextured player position for interactive grass
	var sgt := get_node_or_null("/root/SimpleGrass")
	if sgt:
		sgt.set_player_position(global_position)
