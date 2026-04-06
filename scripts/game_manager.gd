extends Node

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var spawn_container: Node = $SpawnContainer

var _terrain_ready: bool = false


func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Wait for terrain, then spawn local player
	_wait_for_terrain_then_spawn_local.call_deferred()


func _wait_for_terrain_then_spawn_local() -> void:
	# Terrain3D provides built-in collision; wait a few physics frames for it to register
	var terrain := get_parent().get_node_or_null("Terrain3D")
	if terrain:
		print("GameManager: Terrain3D found, waiting for collision to register...")
	else:
		print("GameManager: WARNING - No Terrain3D node found!")

	# Wait for physics server to fully register Terrain3D collision
	for i in range(10):
		await get_tree().physics_frame

	# Verify collision is working with a raycast
	var space_state := get_parent().get_viewport().find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(0, 100, 0), Vector3(0, -100, 0)
	)
	var result := space_state.intersect_ray(query)
	if result:
		print("GameManager: Collision verified! Hit at Y=%.2f" % result.position.y)
	else:
		print("GameManager: WARNING - No collision detected, waiting more frames...")
		for i in range(30):
			await get_tree().physics_frame
		result = space_state.intersect_ray(query)
		if result:
			print("GameManager: Collision verified on retry! Hit at Y=%.2f" % result.position.y)
		else:
			print("GameManager: ERROR - Still no collision! Player may fall through.")

	_terrain_ready = true
	print("GameManager: Spawning players...")

	# Spawn the local player
	if multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		_spawn_player(my_id)

		# If we are the server, also spawn any peers that connected before we got here
		if multiplayer.is_server():
			for peer_id in multiplayer.get_peers():
				_spawn_player(peer_id)
	else:
		# No multiplayer — single player fallback
		_spawn_player(1)


func _spawn_player(peer_id: int) -> void:
	if spawn_container.has_node(str(peer_id)):
		return

	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)

	# Set authority BEFORE adding to tree so _ready() can check it
	player.set_multiplayer_authority(peer_id)
	spawn_container.add_child(player, true)

	# Random spawn offset based on peer_id
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id
	var offset_x := rng.randf_range(-5.0, 5.0)
	var offset_z := rng.randf_range(-5.0, 5.0)
	player.global_position = Vector3(offset_x, 50.0, offset_z)

	# Name label
	var label := player.get_node_or_null("NameLabel")
	if label:
		if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
			label.visible = false  # Don't show own label
		else:
			label.text = "Player %d" % peer_id

	print("Spawned player %d (authority=%d)" % [peer_id, player.get_multiplayer_authority()])


func _remove_player(peer_id: int) -> void:
	var player_node := spawn_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
		print("Removed player %d" % peer_id)


# --- Multiplayer callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	if not _terrain_ready:
		# Terrain not ready yet, will be spawned in _wait_for_terrain_then_spawn_local
		return
	# Server: spawn the new player locally and tell everyone else
	if multiplayer.is_server():
		_spawn_player(peer_id)
		# Tell new peer about all existing players
		for child in spawn_container.get_children():
			var existing_id := int(str(child.name))
			if existing_id != peer_id:
				_rpc_spawn_player.rpc_id(peer_id, existing_id)
		# Tell all OTHER existing peers to spawn the new player
		for existing_peer in multiplayer.get_peers():
			if existing_peer != peer_id:
				_rpc_spawn_player.rpc_id(existing_peer, peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	_remove_player(peer_id)
	if multiplayer.is_server():
		_rpc_remove_player.rpc(peer_id)


func _on_server_disconnected() -> void:
	print("Server disconnected! Returning to lobby...")
	for child in spawn_container.get_children():
		child.queue_free()
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


# --- RPCs ---

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_player(peer_id: int) -> void:
	_spawn_player(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_remove_player(peer_id: int) -> void:
	_remove_player(peer_id)
