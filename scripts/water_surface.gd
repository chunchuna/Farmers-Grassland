@tool
extends MeshInstance3D

## Water surface Y level — should match terrain_generator's water_level
@export var water_level: float = -1.0
## Lake center (fraction of terrain half-size)
@export var lake_center: Vector2 = Vector2(0.15, -0.1)
## Terrain half-size for converting lake_center fraction to world coords
@export var terrain_half_size: Vector2 = Vector2(125, 125)
## Lake radius in world units
@export var lake_radius: float = 18.0
## River width
@export var river_width: float = 6.0
## Terrain size X for river length
@export var terrain_size_x: float = 250.0
## River subdivisions along length
@export var river_segments: int = 80

var _saved_mesh: Mesh


func _ready() -> void:
	_generate_water()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saved_mesh = mesh
		mesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if _saved_mesh:
			mesh = _saved_mesh
			_saved_mesh = null


func _generate_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lake_world := Vector2(lake_center.x * terrain_half_size.x, lake_center.y * terrain_half_size.y)

	# --- Generate lake disc ---
	var lake_segments := 64
	var lake_y := water_level
	for i in range(lake_segments):
		var angle0 := float(i) / lake_segments * TAU
		var angle1 := float(i + 1) / lake_segments * TAU
		var margin := 1.02  # slightly larger than hole to cover edges
		var p0 := Vector3(lake_world.x, lake_y, lake_world.y)
		var p1 := Vector3(
			lake_world.x + cos(angle0) * lake_radius * margin,
			lake_y,
			lake_world.y + sin(angle0) * lake_radius * margin
		)
		var p2 := Vector3(
			lake_world.x + cos(angle1) * lake_radius * margin,
			lake_y,
			lake_world.y + sin(angle1) * lake_radius * margin
		)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(p0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5 + cos(angle0) * 0.5, 0.5 + sin(angle0) * 0.5))
		st.add_vertex(p1)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5 + cos(angle1) * 0.5, 0.5 + sin(angle1) * 0.5))
		st.add_vertex(p2)

	# --- Generate river strip ---
	var river_start_x := lake_world.x + lake_radius * 0.8
	var river_end_x := terrain_size_x * 0.5
	var river_length := river_end_x - river_start_x
	var seg_len := river_length / river_segments

	for i in range(river_segments):
		var x0 := river_start_x + i * seg_len
		var x1 := river_start_x + (i + 1) * seg_len

		# River center Z follows a sine curve (must match terrain carving)
		var z0 := lake_world.y + sin(x0 * 0.04) * 12.0
		var z1 := lake_world.y + sin(x1 * 0.04) * 12.0

		# River widens (must match terrain)
		var half_w0 := river_width * 0.5 * (1.0 + (x0 - river_start_x) * 0.005)
		var half_w1 := river_width * 0.5 * (1.0 + (x1 - river_start_x) * 0.005)

		# Slight margin
		half_w0 *= 1.05
		half_w1 *= 1.05

		var v0l := Vector3(x0, lake_y, z0 - half_w0)
		var v0r := Vector3(x0, lake_y, z0 + half_w0)
		var v1l := Vector3(x1, lake_y, z1 - half_w1)
		var v1r := Vector3(x1, lake_y, z1 + half_w1)

		var u0 := float(i) / river_segments
		var u1 := float(i + 1) / river_segments

		# Triangle 1
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(v0l)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(v1l)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(v0r)

		# Triangle 2
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(v1l)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(v1r)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(v0r)

	st.index()
	mesh = st.commit()
	print("Water surface generated: lake at %s, river from x=%.1f to x=%.1f" % [lake_world, river_start_x, river_end_x])
