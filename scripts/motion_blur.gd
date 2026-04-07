extends ColorRect

## Motion blur driven by camera rotation velocity.
## Attach this to a ColorRect that covers the full screen.

@export var blur_scale: float = 0.05
@export var smoothing: float = 10.0

var _prev_rotation := Vector3.ZERO
var _blur_velocity := Vector2.ZERO

@onready var _material: ShaderMaterial = material


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not _material:
		return

	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	var rot := cam.global_rotation
	var rot_delta := rot - _prev_rotation
	_prev_rotation = rot

	# Map camera rotation delta to screen-space velocity
	var target_vel := Vector2(rot_delta.y, -rot_delta.x) * blur_scale
	_blur_velocity = _blur_velocity.lerp(target_vel, clampf(smoothing * delta, 0.0, 1.0))

	# Clamp to avoid extreme blur
	_blur_velocity = _blur_velocity.clampf(-0.05, 0.05)

	_material.set_shader_parameter("blur_velocity", _blur_velocity)
