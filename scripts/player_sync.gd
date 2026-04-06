extends Node

## Attached to the Player node to sync transform data over the network.
## Works alongside MultiplayerSynchronizer for property-based sync.

@export var sync_rate: float = 20.0  # Updates per second

var _sync_timer: float = 0.0
var _target_position := Vector3.ZERO
var _target_rotation_y: float = 0.0
var _target_head_rotation_x: float = 0.0
var _lerp_speed: float = 15.0

@onready var player: CharacterBody3D = get_parent()
@onready var head: Node3D = player.get_node("Head")


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
			_rpc_sync_transform.rpc(
				player.global_position,
				player.rotation.y,
				head_rot_x
			)
	else:
		# Remote player: interpolate toward received position
		player.global_position = player.global_position.lerp(_target_position, _lerp_speed * delta)
		player.rotation.y = lerp_angle(player.rotation.y, _target_rotation_y, _lerp_speed * delta)
		if head:
			head.rotation.x = lerp_angle(head.rotation.x, _target_head_rotation_x, _lerp_speed * delta)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_transform(pos: Vector3, rot_y: float, head_rot_x: float) -> void:
	_target_position = pos
	_target_rotation_y = rot_y
	_target_head_rotation_x = head_rot_x
