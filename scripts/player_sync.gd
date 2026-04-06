extends Node

## Attached to the Player node to sync transform data over the network.
## Works alongside MultiplayerSynchronizer for property-based sync.

@export var sync_rate: float = 20.0  # Updates per second

var _sync_timer: float = 0.0
var _target_position := Vector3.ZERO
var _target_rotation_y: float = 0.0
var _target_head_rotation_x: float = 0.0
var _remote_speed: float = 0.0
var _lerp_speed: float = 15.0

@onready var player: CharacterBody3D = get_parent()
@onready var head: Node3D = player.get_node("Head")
@onready var player_model: Node3D = player.get_node("PlayerModel")


func _ready() -> void:
	_target_position = player.global_position
	_target_rotation_y = player.rotation.y
	if head:
		_target_head_rotation_x = head.rotation.x


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	var is_local := player.get_multiplayer_authority() == multiplayer.get_unique_id()

	if is_local:
		# Local player: send our position to others
		_sync_timer += delta
		if _sync_timer >= 1.0 / sync_rate:
			_sync_timer = 0.0
			var head_rot_x := head.rotation.x if head else 0.0
			var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
			_rpc_sync_transform.rpc(
				player.global_position,
				player.rotation.y,
				head_rot_x,
				h_speed
			)
	else:
		# Remote player: interpolate toward received position
		player.global_position = player.global_position.lerp(_target_position, _lerp_speed * delta)
		player.rotation.y = lerp_angle(player.rotation.y, _target_rotation_y, _lerp_speed * delta)
		if head:
			head.rotation.x = lerp_angle(head.rotation.x, _target_head_rotation_x, _lerp_speed * delta)
		# Drive animation on remote player model
		if player_model and player_model.has_method("set_movement_blend"):
			var walk_speed: float = player.walk_speed
			var sprint_speed: float = player.sprint_speed
			var blend: float
			if _remote_speed < 0.1:
				blend = 0.0
			elif _remote_speed <= walk_speed:
				blend = remap(_remote_speed, 0.0, walk_speed, 0.0, 0.5)
			else:
				blend = remap(_remote_speed, walk_speed, sprint_speed, 0.5, 1.0)
			player_model.set_movement_blend(blend)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_transform(pos: Vector3, rot_y: float, head_rot_x: float, h_speed: float = 0.0) -> void:
	_target_position = pos
	_target_rotation_y = rot_y
	_target_head_rotation_x = head_rot_x
	_remote_speed = h_speed
