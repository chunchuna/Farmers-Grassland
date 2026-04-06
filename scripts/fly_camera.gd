extends Camera3D

## Movement speed
@export var move_speed: float = 20.0
## Fast movement speed (Shift held)
@export var fast_speed: float = 50.0
## Mouse sensitivity
@export var mouse_sensitivity: float = 0.002

var _velocity := Vector3.ZERO
var _mouse_captured := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		# Clamp pitch
		rotation.x = clamp(rotation.x, -PI * 0.45, PI * 0.45)

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mouse_captured = true

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false


func _physics_process(delta: float) -> void:
	var speed := fast_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
	var input_dir := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		input_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		input_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		input_dir += transform.basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		input_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		input_dir -= Vector3.UP

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	_velocity = _velocity.lerp(input_dir * speed, 8.0 * delta)
	position += _velocity * delta
