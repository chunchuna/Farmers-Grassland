extends Node

## Autoload singleton that ensures all clients load the same map as the host.
## The host stores the selected map path here before changing scenes.
## When a client connects, the server sends the map path via RPC.

var current_map_path: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func _on_peer_connected(peer_id: int) -> void:
	# Server tells the newly connected peer which map to load
	if multiplayer.is_server() and not current_map_path.is_empty():
		_rpc_load_map.rpc_id(peer_id, current_map_path)


@rpc("authority", "call_remote", "reliable")
func _rpc_load_map(scene_path: String) -> void:
	print("MapSync: Server says load map: %s" % scene_path)
	current_map_path = scene_path
	get_tree().change_scene_to_file(scene_path)
