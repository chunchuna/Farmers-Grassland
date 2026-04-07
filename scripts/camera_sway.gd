extends Camera3D

## Handheld camera sway effect for first-person view.
## Combines four layers of natural motion:
##   1. Walk/run head bob (rhythmic up-down + side-to-side + roll)
##   2. Mouse look sway (subtle roll when turning)
##   3. Idle breathing (slow gentle drift when standing still)
##   4. Landing impact (downward dip on landing)
##
## Attach this script to the Camera3D node under Head.
## IMPORTANT: Only position offset and rotation.z (roll) are used.
## Head pitch (rotation.x) is controlled by player.gd on the Head node,
## so this script never touches rotation.x or rotation.y to avoid conflicts.

@export_group("Head Bob")
@export var bob_enabled: bool = true
## Vertical bob amplitude (meters)
@export_range(0.0, 0.1, 0.001) var bob_v_amount: float = 0.02
## Horizontal bob amplitude (meters)
@export_range(0.0, 0.1, 0.001) var bob_h_amount: float = 0.012
## Bob frequency multiplier (higher = faster bob cycle)
@export_range(0.5, 4.0, 0.1) var bob_freq: float = 1.8
## Roll tilt during bob (radians)
@export_range(0.0, 0.03, 0.001) var bob_roll_amount: float = 0.006

@export_group("Mouse Sway")
@export var sway_enabled: bool = true
## How much horizontal mouse movement adds roll tilt (radians per pixel)
@export_range(0.0, 0.001, 0.00005) var sway_roll_amount: float = 0.00015
## How fast the sway roll returns to center
@export_range(1.0, 30.0, 0.5) var sway_recovery: float = 6.0
## Max roll clamp (radians)
@export_range(0.0, 0.1, 0.005) var sway_max_roll: float = 0.03

@export_group("Idle Breathing")
@export var breathe_enabled: bool = true
## Breathing position amplitude (meters)
@export_range(0.0, 0.02, 0.001) var breathe_pos_amount: float = 0.004
## Breathing roll amplitude (radians)
@export_range(0.0, 0.01, 0.0005) var breathe_roll_amount: float = 0.002
## Breathing cycle speed
@export_range(0.3, 3.0, 0.1) var breathe_speed: float = 0.8

@export_group("Landing Impact")
@export var land_enabled: bool = true
## Downward dip on landing (meters)
@export_range(0.0, 0.2, 0.005) var land_dip_amount: float = 0.06
## Recovery speed after landing dip
@export_range(3.0, 20.0, 0.5) var land_recovery: float = 8.0

# Internal state
var _bob_time: float = 0.0
var _sway_roll: float = 0.0
var _mouse_dx: float = 0.0
var _land_offset: float = 0.0
var _was_on_floor: bool = true
var _base_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_base_position = position
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_dx += event.relative.x


func _process(delta: float) -> void:
	# Head -> Player
	var head := get_parent()
	if not head:
		return
	var player := head.get_parent() as CharacterBody3D
	if not player or not _is_local():
		return

	# Don't apply sway in third-person
	if not current:
		position = _base_position
		rotation = Vector3.ZERO
		return

	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var is_on_floor: bool = player.is_on_floor()
	var is_moving := h_speed > 0.3 and is_on_floor

	# ── 1. Head bob ──
	var bob_pos := Vector3.ZERO
	var bob_roll := 0.0
	if bob_enabled and is_moving:
		var freq := bob_freq * clampf(h_speed / 3.0, 0.6, 2.0)
		_bob_time += delta * freq * TAU
		bob_pos.y = sin(_bob_time) * bob_v_amount
		bob_pos.x = cos(_bob_time * 0.5) * bob_h_amount
		bob_roll = sin(_bob_time * 0.5) * bob_roll_amount
	else:
		# Smoothly decay bob time so it fades out naturally
		_bob_time = lerp(_bob_time, 0.0, delta * 5.0)

	# ── 2. Mouse look sway (roll only — no pitch/yaw interference) ──
	if sway_enabled:
		_sway_roll += _mouse_dx * sway_roll_amount
		_sway_roll = clampf(_sway_roll, -sway_max_roll, sway_max_roll)
		_sway_roll = lerp(_sway_roll, 0.0, clampf(sway_recovery * delta, 0.0, 1.0))
	_mouse_dx = 0.0

	# ── 3. Idle breathing ──
	var breathe_pos := Vector3.ZERO
	var breathe_roll := 0.0
	if breathe_enabled and not is_moving:
		var t := Time.get_ticks_msec() / 1000.0 * breathe_speed
		breathe_pos.y = sin(t * TAU) * breathe_pos_amount
		breathe_pos.x = sin(t * 0.7 * TAU) * breathe_pos_amount * 0.5
		breathe_roll = sin(t * 0.5 * TAU) * breathe_roll_amount

	# ── 4. Landing impact ──
	if land_enabled:
		if is_on_floor and not _was_on_floor:
			var fall_speed := absf(player.velocity.y)
			_land_offset = -land_dip_amount * clampf(fall_speed / 10.0, 0.3, 1.0)
		_land_offset = lerp(_land_offset, 0.0, clampf(land_recovery * delta, 0.0, 1.0))
	_was_on_floor = is_on_floor

	# ── Apply ──
	# Position: bob + breathing + landing (local offset from base)
	position = _base_position + bob_pos + breathe_pos + Vector3(0, _land_offset, 0)
	# Roll only: bob roll + mouse sway roll + breathing roll
	rotation.z = bob_roll + _sway_roll + breathe_roll


func _is_local() -> bool:
	var head := get_parent()
	if not head:
		return false
	var player := head.get_parent() as CharacterBody3D
	if not player:
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.get_multiplayer_authority() == multiplayer.get_unique_id()
