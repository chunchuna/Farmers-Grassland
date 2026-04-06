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

@onready var camera: Camera3D = $Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _physics_ready: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Disable physics until terrain collision is registered
	set_physics_process(false)
	_wait_for_terrain.call_deferred()


func _wait_for_terrain() -> void:
	# Wait a few frames so the terrain collision shape is fully registered
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Raycast down to find the terrain surface and place player on it
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 50, 0)
	var to := global_position + Vector3(0, -100, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		global_position = result.position + Vector3(0, 1.0, 0)
	_physics_ready = true
	set_physics_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Horizontal rotation on the body
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Vertical rotation on the camera
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta
	
	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Also support Space key directly for jump
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor() and velocity.y <= 0.0:
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
