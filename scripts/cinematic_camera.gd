@tool
extends Node
class_name CinematicCamera

## Reusable cinematic camera system.
## Supports: orbit, dolly, pan, montage, and editor-configured sequences.
##
## Editor workflow:
##   1. Add CinematicCamera as a child node in your scene
##   2. Set points[] in the Inspector (add CinematicPoint resources)
##   3. Set default_look_at_target to the node the camera should face
##   4. Call play_sequence() from code, or check auto_play to start on _ready
##
## Code workflow:
##   var cc = CinematicCamera.new()
##   add_child(cc)
##   cc.play_montage(points, target, 5.0)
##   await cc.finished

signal finished

@export_group("Sequence (Editor)")
## Cinematic points configurable in the Inspector. Add/remove freely.
@export var points: Array[CinematicPoint] = []
## Default node to look at (used when a point's look_at_node is empty).
@export var default_look_at_target: NodePath = NodePath()
## Default FOV when a point's fov is 0.
@export_range(30, 120, 1) var default_fov: float = 55.0
## Show the player's third-person model during the cinematic.
@export var show_player_model: bool = true
## Auto-play the sequence on _ready (useful for cutscenes).
@export var auto_play: bool = false

enum ShotType { NONE, ORBIT, DOLLY, PAN, MONTAGE, SEQUENCE }

var _camera: Camera3D = null
var _prev_camera: Camera3D = null
var _active: bool = false
var _time: float = 0.0
var _duration: float = 3.0
var _shot_type: ShotType = ShotType.NONE

# Player model visibility
var _player_ref: CharacterBody3D = null
var _player_model_was_visible: bool = false

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

# Montage (code API)
var _montage_points: Array = []
var _montage_look_at: Vector3
var _montage_segment_count: int = 0

# Sequence (editor points)
var _seq_points: Array[CinematicPoint] = []
var _seq_durations: Array[float] = []  # cumulative end times
var _seq_total: float = 0.0
var _seq_default_look_at: Vector3 = Vector3.ZERO

var _ease_in: bool = true
var _ease_out: bool = true
var _fov: float = 60.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(false)
	if auto_play and points.size() > 0:
		call_deferred("play_sequence")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _active:
		return
	_time += delta
	if _time >= _duration:
		_update_shot(1.0)
		_end_shot()
		return
	match _shot_type:
		ShotType.SEQUENCE:
			_update_shot(_time)  # Sequence uses absolute time
		_:
			_update_shot(_apply_easing(_time / _duration))


func is_playing() -> bool:
	return _active


# ── Editor-configured sequence ──

## Play the sequence defined by the exported points array.
func play_sequence() -> void:
	if points.is_empty():
		push_warning("CinematicCamera: No points configured.")
		return
	_seq_points = points.duplicate()
	_seq_durations.clear()
	_seq_total = 0.0
	for pt in _seq_points:
		_seq_total += pt.duration
		_seq_durations.append(_seq_total)

	# Resolve default look-at
	if default_look_at_target != NodePath():
		var target_node := get_node_or_null(default_look_at_target)
		if target_node and target_node is Node3D:
			_seq_default_look_at = (target_node as Node3D).global_position
	_fov = default_fov
	_ease_in = false
	_ease_out = false
	_begin_shot(ShotType.SEQUENCE, _seq_total)


# ── Programmatic API ──

## Orbit around center.
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


## Montage: sequence of viewpoints with slow drift, all looking at a target.
func play_montage(points_array: Array, look_at_target: Vector3,
		duration: float, fov: float = 60.0) -> void:
	_montage_points = points_array
	_montage_look_at = look_at_target
	_montage_segment_count = points_array.size()
	_fov = fov
	_ease_in = false
	_ease_out = false
	_begin_shot(ShotType.MONTAGE, duration)


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

	# Show player model during cinematic
	if show_player_model:
		_show_player()

	_camera = Camera3D.new()
	_camera.fov = _fov
	get_tree().current_scene.add_child(_camera)

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

	# Restore player model visibility
	_restore_player()

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

		ShotType.MONTAGE:
			if _montage_segment_count == 0:
				return
			var seg_f := t * _montage_segment_count
			var seg_idx := mini(int(seg_f), _montage_segment_count - 1)
			var seg_t := clampf(seg_f - seg_idx, 0.0, 1.0)
			seg_t = seg_t * seg_t * (3.0 - 2.0 * seg_t)
			var pt: Dictionary = _montage_points[seg_idx]
			var from_pos: Vector3 = pt["from"]
			var to_pos: Vector3 = pt["to"]
			_camera.global_position = from_pos.lerp(to_pos, seg_t)
			_camera.look_at(_montage_look_at, Vector3.UP)

		ShotType.SEQUENCE:
			_update_sequence(t)  # t is absolute time here


func _update_sequence(abs_time: float) -> void:
	if _seq_points.is_empty():
		return
	# Find which segment we're in based on cumulative durations
	var seg_idx := 0
	for i in range(_seq_durations.size()):
		if abs_time <= _seq_durations[i]:
			seg_idx = i
			break
		seg_idx = i

	var pt: CinematicPoint = _seq_points[seg_idx]
	var seg_start := 0.0 if seg_idx == 0 else _seq_durations[seg_idx - 1]
	var seg_dur := pt.duration
	var seg_t := clampf((abs_time - seg_start) / seg_dur, 0.0, 1.0)
	# Smooth easing within segment
	seg_t = seg_t * seg_t * (3.0 - 2.0 * seg_t)

	# Position: drift from position to position + drift
	_camera.global_position = pt.position.lerp(pt.position + pt.drift, seg_t)

	# FOV per point
	var seg_fov := pt.fov if pt.fov > 0.0 else default_fov
	_camera.fov = seg_fov

	# Look-at: per-point node or default
	var look_pos := _seq_default_look_at
	if pt.look_at_node != NodePath():
		var node := get_node_or_null(pt.look_at_node)
		if node and node is Node3D:
			look_pos = (node as Node3D).global_position
	_camera.look_at(look_pos, Vector3.UP)


func _show_player() -> void:
	_player_ref = _find_local_player()
	if _player_ref:
		var model := _player_ref.get_node_or_null("PlayerModel")
		if model:
			_player_model_was_visible = model.visible
			model.visible = true


func _restore_player() -> void:
	if _player_ref and is_instance_valid(_player_ref):
		var model := _player_ref.get_node_or_null("PlayerModel")
		if model:
			model.visible = _player_model_was_visible
	_player_ref = null


func _find_local_player() -> CharacterBody3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody3D:
			if not p.multiplayer.has_multiplayer_peer():
				return p
			if p.get_multiplayer_authority() == p.multiplayer.get_unique_id():
				return p
	return null


func _apply_easing(t: float) -> float:
	if _ease_in and _ease_out:
		return t * t * (3.0 - 2.0 * t)
	elif _ease_in:
		return t * t
	elif _ease_out:
		return 1.0 - (1.0 - t) * (1.0 - t)
	return t
