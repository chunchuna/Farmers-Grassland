extends Node3D

## Chunk size in world units
@export var chunk_size: float = 16.0
## View distance for grass (chunks beyond this are unloaded)
@export var view_distance: float = 60.0
## Grass blades per chunk at closest distance
@export var blades_per_chunk_near: int = 600
## Grass blades per chunk at farthest distance
@export var blades_per_chunk_far: int = 100
## Grass blade height
@export var blade_height: float = 0.3
## Grass blade width
@export var blade_width: float = 0.05
## Minimum terrain height to place grass (skip water)
@export var min_terrain_height: float = -0.5
## Push radius for player interaction
@export var push_radius: float = 3.0
## Push strength for player interaction
@export var push_strength: float = 2.0
## How often to check for chunk updates (seconds)
@export var update_interval: float = 0.3
## Grass shader material (assigned in scene)
@export var grass_material: ShaderMaterial

var _terrain_mesh: Node = null
var _material: ShaderMaterial = null
var _blade_mesh: Mesh = null
var _chunks: Dictionary = {}  # Vector2i -> MultiMeshInstance3D
var _last_player_chunk := Vector2i(-9999, -9999)
var _update_timer: float = 0.0
var _chunks_to_load: Array[Vector2i] = []
var _loading: bool = false


func _ready() -> void:
	_find_terrain()
	if _terrain_mesh == null:
		push_warning("GrassSpawner: No TerrainMesh found!")
		return

	if not _terrain_mesh.mesh:
		await _terrain_mesh.terrain_ready

	_build_blade_mesh()

	if grass_material:
		_material = grass_material
		_material.set_shader_parameter("grass_height", blade_height)
		_material.set_shader_parameter("push_radius", push_radius)
		_material.set_shader_parameter("push_strength", push_strength)

	print("GrassSpawner: Chunked LOD system ready (chunk=%dm, view=%dm)" % [int(chunk_size), int(view_distance)])


func _process(delta: float) -> void:
	_update_player_shader_positions()

	_update_timer += delta
	if _update_timer < update_interval:
		return
	_update_timer = 0.0

	var player_pos: Variant = _get_local_player_position()
	if player_pos == null:
		return

	var px: float = player_pos.x
	var pz: float = player_pos.z
	var player_chunk := Vector2i(int(floorf(px / chunk_size)), int(floorf(pz / chunk_size)))

	# Only do full update if player moved to a new chunk
	if player_chunk == _last_player_chunk:
		# Still process queued chunks
		_process_chunk_queue()
		return
	_last_player_chunk = player_chunk

	var chunk_radius := int(ceilf(view_distance / chunk_size))
	var needed_chunks: Dictionary = {}

	# Determine which chunks should exist
	for cz in range(player_chunk.y - chunk_radius, player_chunk.y + chunk_radius + 1):
		for cx in range(player_chunk.x - chunk_radius, player_chunk.x + chunk_radius + 1):
			var chunk_center := Vector2((cx + 0.5) * chunk_size, (cz + 0.5) * chunk_size)
			var dist := Vector2(px, pz).distance_to(chunk_center)
			if dist <= view_distance:
				var key := Vector2i(cx, cz)
				needed_chunks[key] = true

	# Unload chunks that are too far
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _chunks:
		if not needed_chunks.has(key):
			to_remove.append(key)
	for key in to_remove:
		var chunk_node: MultiMeshInstance3D = _chunks[key]
		chunk_node.queue_free()
		_chunks.erase(key)

	# Queue new chunks to load (spread across frames)
	_chunks_to_load.clear()
	for key: Vector2i in needed_chunks:
		if not _chunks.has(key):
			_chunks_to_load.append(key)

	# Sort by distance: load closest chunks first
	_chunks_to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Vector2(px, pz).distance_squared_to(Vector2((a.x + 0.5) * chunk_size, (a.y + 0.5) * chunk_size))
		var db := Vector2(px, pz).distance_squared_to(Vector2((b.x + 0.5) * chunk_size, (b.y + 0.5) * chunk_size))
		return da < db
	)

	_process_chunk_queue()


func _process_chunk_queue() -> void:
	# Load a few chunks per frame to avoid stutter
	var loaded := 0
	var max_per_frame := 4
	while _chunks_to_load.size() > 0 and loaded < max_per_frame:
		var key: Vector2i = _chunks_to_load.pop_front()
		_create_chunk(key)
		loaded += 1


func _create_chunk(key: Vector2i) -> void:
	if _terrain_mesh == null or _blade_mesh == null:
		return

	var chunk_origin := Vector2(key.x * chunk_size, key.y * chunk_size)
	var chunk_center := chunk_origin + Vector2(chunk_size * 0.5, chunk_size * 0.5)

	# Check if chunk is within terrain bounds
	var terrain_size: Vector2 = _terrain_mesh.terrain_size
	var half := terrain_size * 0.5
	if absf(chunk_center.x) > half.x or absf(chunk_center.y) > half.y:
		return

	# Calculate LOD: how many blades based on distance from player
	var player_pos: Variant = _get_local_player_position()
	var dist := 0.0
	if player_pos != null:
		dist = Vector2(player_pos.x, player_pos.z).distance_to(chunk_center)

	var lod_t := clampf(dist / view_distance, 0.0, 1.0)
	var blade_count := int(lerpf(blades_per_chunk_near, blades_per_chunk_far, lod_t * lod_t))
	if blade_count < 10:
		return

	# Create MultiMesh for this chunk
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = blade_count
	mm.mesh = _blade_mesh

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) & 0x7FFFFFFF

	var placed := 0
	var attempts := 0
	var max_attempts := blade_count * 3

	while placed < blade_count and attempts < max_attempts:
		attempts += 1
		var lx := rng.randf_range(0, chunk_size)
		var lz := rng.randf_range(0, chunk_size)
		var wx := chunk_origin.x + lx
		var wz := chunk_origin.y + lz

		# Check terrain bounds
		if absf(wx) > half.x or absf(wz) > half.y:
			continue

		var wy: float = _terrain_mesh.get_height_at(wx, wz)
		if wy < min_terrain_height:
			continue

		var angle := rng.randf() * TAU
		var scale_var := rng.randf_range(0.6, 1.4)

		var t := Transform3D()
		t = t.scaled(Vector3(scale_var, scale_var, scale_var))
		t = t.rotated(Vector3.UP, angle)
		t.origin = Vector3(wx, wy, wz)
		mm.set_instance_transform(placed, t)
		placed += 1

	# Trim unused instances
	if placed < blade_count:
		mm.instance_count = placed

	if placed == 0:
		return

	# Create the node
	var chunk_node := MultiMeshInstance3D.new()
	chunk_node.multimesh = mm
	chunk_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material:
		chunk_node.material_override = _material
	chunk_node.name = "GrassChunk_%d_%d" % [key.x, key.y]
	add_child(chunk_node)
	_chunks[key] = chunk_node


func _update_player_shader_positions() -> void:
	if _material == null:
		return
	var players := get_tree().get_nodes_in_group("players")
	_material.set_shader_parameter("player_count", players.size())

	var positions: Array = []
	for i in range(8):
		if i < players.size():
			positions.append(players[i].global_position)
		else:
			positions.append(Vector3(99999, 99999, 99999))
	_material.set_shader_parameter("player_positions", positions)


func _get_local_player_position() -> Variant:
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if p.has_method("_is_local_player"):
			if p._is_local_player():
				return p.global_position
	# Fallback: use first player or camera
	if players.size() > 0:
		return players[0].global_position
	var cam := get_viewport().get_camera_3d()
	if cam:
		return cam.global_position
	return null


func _find_terrain() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_terrain_mesh = _find_terrain_recursive(root)


func _find_terrain_recursive(node: Node) -> Node:
	if node.has_method("get_height_at"):
		return node
	for child in node.get_children():
		var result := _find_terrain_recursive(child)
		if result:
			return result
	return null


func _build_blade_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := blade_width * 0.5
	var segments := 3

	for i in range(segments):
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var y0 := t0 * blade_height
		var y1 := t1 * blade_height
		var w0 := hw * (1.0 - t0 * 0.7)
		var w1 := hw * (1.0 - t1 * 0.7)
		var normal := Vector3(0, 0, 1)

		st.set_normal(normal)
		st.set_uv(Vector2(0, t0))
		st.add_vertex(Vector3(-w0, y0, 0))
		st.set_normal(normal)
		st.set_uv(Vector2(1, t0))
		st.add_vertex(Vector3(w0, y0, 0))
		st.set_normal(normal)
		st.set_uv(Vector2(1, t1))
		st.add_vertex(Vector3(w1, y1, 0))

		st.set_normal(normal)
		st.set_uv(Vector2(0, t0))
		st.add_vertex(Vector3(-w0, y0, 0))
		st.set_normal(normal)
		st.set_uv(Vector2(1, t1))
		st.add_vertex(Vector3(w1, y1, 0))
		st.set_normal(normal)
		st.set_uv(Vector2(0, t1))
		st.add_vertex(Vector3(-w1, y1, 0))

	# Tip triangle
	var t_last := float(segments - 1) / segments
	var y_last := t_last * blade_height
	var w_last := hw * (1.0 - t_last * 0.7)
	st.set_normal(Vector3(0, 0, 1))
	st.set_uv(Vector2(0, t_last))
	st.add_vertex(Vector3(-w_last, y_last, 0))
	st.set_normal(Vector3(0, 0, 1))
	st.set_uv(Vector2(1, t_last))
	st.add_vertex(Vector3(w_last, y_last, 0))
	st.set_normal(Vector3(0, 0, 1))
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(Vector3(0, blade_height, 0))

	_blade_mesh = st.commit()
