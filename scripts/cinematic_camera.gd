extends Node
class_name CinematicCamera

## Reusable cinematic camera system.
## Supports: orbit, dolly, pan shots. Freezes player during playback.
## Usage:
##   var cc = CinematicCamera.new()
##   add_child(cc)
##   cc.play_orbit(target, 6.0, 3.5, 3.0)
##   await cc.finished

signal finished

enum ShotType { NONE, ORBIT, DOLLY, PAN }

var _camera: Camera3D = null
var _prev_camera: Camera3D = null
var _active: bool = false
var _time: float = 0.0
var _duration: float = 3.0
var _shot_type: ShotType = ShotType.NONE

# Orbit
var _orbit_center: Vector3
var _orbit_radius: float = 6.0
var _orbit_height: float = 3.5
var _orbit_start_angle: float = 0.0
var _orbit_turns: float = 1.0

# Dolly
var _dolly_from: Vector3
var _dolly_to: Vector3
var _dolly_look_at: Vector3

# Pan
var _pan_position: Vector3
var _pan_from_target: Vector3
var _pan_to_target: Vector3

var _ease_in: bool = true
var _ease_out: bool = true
var _fov: float = 60.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _time >= _duration:
		_update_shot(1.0)
		_end_shot()
		return
	_update_shot(_apply_easing(_time / _duration))


func is_playing() -> bool:
	return _active


## Orbit around center. Starts from start_angle (radians), does `turns` full rotations.
func play_orbit(center: Vector3, radius: float, height: float, duration: float,
		turns: float = 1.0, start_angle: float = 0.0, fov: float = 60.0,
		ease_in: bool = true, ease_out: bool = true) -> void:
	_orbit_center = center
	_orbit_radius = radius
	_orbit_height = height
	_orbit_turns = turns
	_orbit_start_angle = start_angle
	_fov = fov
	_ease_in = ease_in
	_ease_out = ease_out
	_begin_shot(ShotType.ORBIT, duration)


## Dolly: move camera from A to B while looking at a target.
func play_dolly(from: Vector3, to: Vector3, look_at_target: Vector3,
		duration: float, fov: float = 60.0,
		ease_in: bool = true, ease_out: bool = true) -> void:
	_dolly_from = from
	_dolly_to = to
	_dolly_look_at = look_at_target
	_fov = fov
	_ease_in = ease_in
	_ease_out = ease_out
	_begin_shot(ShotType.DOLLY, duration)


## Pan: camera stays in place, rotates from looking at A to looking at B.
func play_pan(cam_position: Vector3, from_target: Vector3, to_target: Vector3,
		duration: float, fov: float = 60.0,
		ease_in: bool = true, ease_out: bool = true) -> void:
	_pan_position = cam_position
	_pan_from_target = from_target
	_pan_to_target = to_target
	_fov = fov
	_ease_in = ease_in
	_ease_out = ease_out
	_begin_shot(ShotType.PAN, duration)


## Stop current shot immediately and restore player camera.
func stop() -> void:
	if _active:
		_end_shot()


# ── Internal ──

func _begin_shot(type: ShotType, duration: float) -> void:
	_shot_type = type
	_duration = duration
	_time = 0.0

	_prev_camera = get_viewport().get_camera_3d()

	_camera = Camera3D.new()
	_camera.fov = _fov
	get_tree().current_scene.add_child(_camera)

	# Set initial position
	_update_shot(0.0)
	_camera.make_current()

	_active = true
	set_process(true)


func _end_shot() -> void:
	_active = false
	set_process(false)
	_shot_type = ShotType.NONE

	if _prev_camera and is_instance_valid(_prev_camera):
		_prev_camera.make_current()
	_prev_camera = null

	if _camera and is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null

	finished.emit()


func _update_shot(t: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		return
	match _shot_type:
		ShotType.ORBIT:
			var angle := _orbit_start_angle + t * TAU * _orbit_turns
			var pos := _orbit_center + Vector3(
				cos(angle) * _orbit_radius,
				_orbit_height,
				sin(angle) * _orbit_radius
			)
			_camera.global_position = pos
			_camera.look_at(_orbit_center, Vector3.UP)

		ShotType.DOLLY:
			_camera.global_position = _dolly_from.lerp(_dolly_to, t)
			_camera.look_at(_dolly_look_at, Vector3.UP)

		ShotType.PAN:
			_camera.global_position = _pan_position
			var from_dir := (_pan_from_target - _pan_position).normalized()
			var to_dir := (_pan_to_target - _pan_position).normalized()
			var from_basis := Basis.looking_at(from_dir, Vector3.UP)
			var to_basis := Basis.looking_at(to_dir, Vector3.UP)
			var quat := Quaternion(from_basis).slerp(Quaternion(to_basis), t)
			_camera.global_transform.basis = Basis(quat)


func _apply_easing(t: float) -> float:
	if _ease_in and _ease_out:
		return t * t * (3.0 - 2.0 * t)  # smoothstep
	elif _ease_in:
		return t * t
	elif _ease_out:
		return 1.0 - (1.0 - t) * (1.0 - t)
	return t
