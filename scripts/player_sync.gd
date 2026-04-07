extends Node

## Attached to the Player node to sync transform data over the network.
## Syncs position, body rotation, head rotation, horizontal speed,
## vertical velocity (for jump), and on_floor state.

@export var sync_rate: float = 20.0  # Updates per second

var _sync_timer: float = 0.0

# --- Remote interpolation targets ---
var _target_position := Vector3.ZERO
var _prev_position := Vector3.ZERO
var _target_rotation_y: float = 0.0
var _target_head_rotation_x: float = 0.0
var _remote_h_speed: float = 0.0
var _remote_vel_y: float = 0.0
var _remote_on_floor: bool = true
var _current_blend: float = 0.0  # Smoothed animation blend for remote players

var _remote_flashlight: bool = false

var _pos_lerp_speed: float = 12.0
var _rot_lerp_speed: float = 15.0
var _anim_blend_speed: float = 8.0  # How fast remote animation blends

@onready var player: CharacterBody3D = get_parent()
@onready var head: Node3D = player.get_node("Head")
@onready var player_model: Node3D = player.get_node("PlayerModel")


func _ready() -> void:
	_target_position = player.global_position
	_prev_position = player.global_position
	_target_rotation_y = player.rotation.y
	if head:
		_target_head_rotation_x = head.rotation.x


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	var is_local := player.get_multiplayer_authority() == multiplayer.get_unique_id()

	if is_local:
		_send_local_state(delta)
	else:
		_interpolate_remote(delta)


func _send_local_state(delta: float) -> void:
	_sync_timer += delta
	if _sync_timer < 1.0 / sync_rate:
		return
	_sync_timer = 0.0

	var head_rot_x := head.rotation.x if head else 0.0
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_rpc_sync_state.rpc(
		player.global_position,
		player.rotation.y,
		head_rot_x,
		h_speed,
		player.velocity.y,
		player.is_on_floor()
	)


func _interpolate_remote(delta: float) -> void:
	# --- Position: lerp XZ, handle Y with gravity when airborne ---
	var current_pos := player.global_position
	var target_xz := Vector3(_target_position.x, current_pos.y, _target_position.z)
	var new_pos := current_pos.lerp(target_xz, _pos_lerp_speed * delta)

	if _remote_on_floor:
		# On ground: lerp Y toward target
		new_pos.y = lerpf(current_pos.y, _target_position.y, _pos_lerp_speed * delta)
	else:
		# Airborne: apply received velocity_y + gravity for smooth jump arc
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		_remote_vel_y -= gravity * 1.5 * delta
		new_pos.y = current_pos.y + _remote_vel_y * delta
		# Still gently pull toward authoritative Y to prevent drift
		new_pos.y = lerpf(new_pos.y, _target_position.y, 2.0 * delta)

	player.global_position = new_pos

	# --- Rotation ---
	player.rotation.y = lerp_angle(player.rotation.y, _target_rotation_y, _rot_lerp_speed * delta)
	if head:
		head.rotation.x = lerp_angle(head.rotation.x, _target_head_rotation_x, _rot_lerp_speed * delta)

	# --- Animation: smooth blend for remote player ---
	if player_model and player_model.has_method("set_movement_blend"):
		var walk_speed: float = player.walk_speed
		var sprint_speed: float = player.sprint_speed
		var target_blend: float
		if _remote_h_speed < 0.1:
			target_blend = 0.0
		elif _remote_h_speed <= walk_speed:
			target_blend = remap(_remote_h_speed, 0.0, walk_speed, 0.0, 0.5)
		else:
			target_blend = remap(_remote_h_speed, walk_speed, sprint_speed, 0.5, 1.0)
		target_blend = clampf(target_blend, 0.0, 1.0)
		_current_blend = lerpf(_current_blend, target_blend, clampf(_anim_blend_speed * delta, 0.0, 1.0))
		player_model.set_movement_blend(_current_blend)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_state(pos: Vector3, rot_y: float, head_rot_x: float, h_speed: float, vel_y: float, on_floor: bool) -> void:
	# Validate: only accept data from the player's authority
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != player.get_multiplayer_authority():
		return

	_prev_position = _target_position
	_target_position = pos
	_target_rotation_y = rot_y
	_target_head_rotation_x = head_rot_x
	_remote_h_speed = h_speed
	_remote_vel_y = vel_y
	_remote_on_floor = on_floor


## Called by local player when flashlight is toggled
func sync_flashlight(enabled: bool) -> void:
	_rpc_sync_flashlight.rpc(enabled)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_flashlight(enabled: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != player.get_multiplayer_authority():
		return
	_remote_flashlight = enabled
	if player.has_method("set_flashlight"):
		player.set_flashlight(enabled)
