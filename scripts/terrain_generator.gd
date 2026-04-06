@tool
extends MeshInstance3D

## Terrain size in units (X and Z)
@export var terrain_size: Vector2 = Vector2(100, 100)
## Number of subdivisions along each axis
@export var subdivisions: Vector2i = Vector2i(200, 200)
## Maximum height of the terrain
@export var max_height: float = 12.0
## Noise frequency — lower = broader hills, higher = more jagged
@export var noise_frequency: float = 0.02
## Secondary noise frequency for detail
@export var detail_frequency: float = 0.08
## Detail noise strength (relative to max_height)
@export_range(0.0, 1.0) var detail_strength: float = 0.25
## Noise seed
@export var noise_seed: int = 42
## Radius of the flat area in the center (fraction of half-size, 0.0-1.0)
@export_range(0.0, 1.0) var flat_radius: float = 0.45
## How steeply the terrain rises at the edges
@export_range(0.1, 10.0) var edge_steepness: float = 3.0
## Mountain height at the edges (multiplier on max_height)
@export_range(0.0, 5.0) var mountain_multiplier: float = 2.5
## Lake center position (fraction of terrain, 0-1 from center)
@export var lake_center: Vector2 = Vector2(0.15, -0.1)
## Lake radius in world units
@export var lake_radius: float = 18.0
## Lake depth below surface
@export var lake_depth: float = 3.0
## River width in world units
@export var river_width: float = 6.0
## River depth below surface
@export var river_depth: float = 1.8
## Water surface Y level
@export var water_level: float = -1.0
## Click to regenerate terrain in editor (resets sculpt!)
@export var regenerate: bool = false:
	set(value):
		regenerate = false
		if Engine.is_editor_hint():
			sculpt_overlay = PackedFloat32Array()
			_generate_terrain()
## Click to clear all sculpt modifications
@export var clear_sculpt: bool = false:
	set(value):
		clear_sculpt = false
		if Engine.is_editor_hint():
			sculpt_overlay = PackedFloat32Array()
			_generate_terrain()
## Per-vertex sculpt height overlay (saved with scene)
@export var sculpt_overlay: PackedFloat32Array = PackedFloat32Array()

signal terrain_ready

var _noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _saved_mesh: Mesh  # Holds mesh reference during editor save
var _base_heights: PackedFloat32Array  # Heights from noise generation (no sculpt)


func _ready() -> void:
	if Engine.is_editor_hint():
		# In editor: generate immediately for preview
		_generate_terrain()
	else:
		# At runtime: defer so the full scene tree is built first
		_generate_terrain.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		# Before editor saves: stash and clear the mesh so it won't be baked into .tscn
		_saved_mesh = mesh
		mesh = null
		# If sculpt overlay is all zeros, clear it to keep scene file small
		if sculpt_overlay.size() > 0:
			var has_data := false
			for v in sculpt_overlay:
				if absf(v) > 0.001:
					has_data = true
					break
			if not has_data:
				sculpt_overlay = PackedFloat32Array()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		# After editor saves: restore the mesh for preview
		if _saved_mesh:
			mesh = _saved_mesh
			_saved_mesh = null


func _generate_terrain() -> void:
	# Setup primary noise
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5

	# Setup detail noise
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.seed = noise_seed + 100
	_detail_noise.frequency = detail_frequency
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_lacunarity = 2.0
	_detail_noise.fractal_gain = 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var verts_x: int = subdivisions.x + 1
	var verts_z: int = subdivisions.y + 1
	var step_x: float = terrain_size.x / subdivisions.x
	var step_z: float = terrain_size.y / subdivisions.y
	var origin := Vector3(-terrain_size.x * 0.5, 0.0, -terrain_size.y * 0.5)

	# Build height map
	var heights: Array[float] = []
	heights.resize(verts_x * verts_z)

	var half_x: float = terrain_size.x * 0.5
	var half_z: float = terrain_size.y * 0.5
	var flat_dist_x: float = half_x * flat_radius
	var flat_dist_z: float = half_z * flat_radius

	for z in range(verts_z):
		for x in range(verts_x):
			var world_x: float = origin.x + x * step_x
			var world_z: float = origin.z + z * step_z

			# Distance from center as a normalized 0-1 value
			var dx: float = absf(world_x) / half_x
			var dz: float = absf(world_z) / half_z
			var dist: float = maxf(dx, dz)  # square-ish falloff

			# Height multiplier: 0 in flat zone, ramps up toward edges
			var edge_t: float = clampf((dist - flat_radius) / (1.0 - flat_radius), 0.0, 1.0)
			# Smooth S-curve with steepness control
			var height_mult: float = pow(edge_t, edge_steepness)

			# Base noise terrain
			var h: float = _noise.get_noise_2d(world_x, world_z) * max_height
			h += _detail_noise.get_noise_2d(world_x, world_z) * max_height * detail_strength

			# Mountains at edges, flat in center
			# In the flat zone: only very subtle undulation
			# At edges: full noise + mountain boost
			var flat_undulation: float = _noise.get_noise_2d(world_x, world_z) * max_height * 0.08
			h = lerpf(flat_undulation, h * mountain_multiplier, height_mult)

			# Carve lake
			var lake_world := Vector2(lake_center.x * half_x, lake_center.y * half_z)
			var dist_to_lake := Vector2(world_x, world_z).distance_to(lake_world)
			if dist_to_lake < lake_radius:
				var lake_t := 1.0 - (dist_to_lake / lake_radius)
				lake_t = lake_t * lake_t * (3.0 - 2.0 * lake_t)  # smoothstep
				var lake_floor := water_level - lake_depth * lake_t
				h = minf(h, lerpf(h, lake_floor, lake_t))

			# Carve river — flows from lake center toward +X edge
			var river_start_x := lake_world.x + lake_radius * 0.8
			if world_x > river_start_x:
				# River path: slight sine curve
				var river_center_z := lake_world.y + sin(world_x * 0.04) * 12.0
				var dist_to_river := absf(world_z - river_center_z)
				var half_w := river_width * 0.5
				# River widens slightly as it goes
				var widen := 1.0 + (world_x - river_start_x) * 0.005
				half_w *= widen
				if dist_to_river < half_w:
					var river_t := 1.0 - (dist_to_river / half_w)
					river_t = river_t * river_t * (3.0 - 2.0 * river_t)
					var river_floor := water_level - river_depth * river_t
					h = minf(h, lerpf(h, river_floor, river_t))

			heights[z * verts_x + x] = h

	# Store base heights for sculpting
	_base_heights = PackedFloat32Array(heights)

	# Apply sculpt overlay if it exists and matches size
	if sculpt_overlay.size() == heights.size():
		for i in range(heights.size()):
			heights[i] += sculpt_overlay[i]
	elif sculpt_overlay.size() > 0 and sculpt_overlay.size() != heights.size():
		push_warning("Sculpt overlay size mismatch, ignoring. Expected %d got %d" % [heights.size(), sculpt_overlay.size()])
		sculpt_overlay = PackedFloat32Array()

	# Build mesh triangles
	for z in range(subdivisions.y):
		for x in range(subdivisions.x):
			var i00: int = z * verts_x + x
			var i10: int = z * verts_x + x + 1
			var i01: int = (z + 1) * verts_x + x
			var i11: int = (z + 1) * verts_x + x + 1

			var v00 := Vector3(origin.x + x * step_x, heights[i00], origin.z + z * step_z)
			var v10 := Vector3(origin.x + (x + 1) * step_x, heights[i10], origin.z + z * step_z)
			var v01 := Vector3(origin.x + x * step_x, heights[i01], origin.z + (z + 1) * step_z)
			var v11 := Vector3(origin.x + (x + 1) * step_x, heights[i11], origin.z + (z + 1) * step_z)

			# UV coordinates
			var uv00 := Vector2(float(x) / subdivisions.x, float(z) / subdivisions.y)
			var uv10 := Vector2(float(x + 1) / subdivisions.x, float(z) / subdivisions.y)
			var uv01 := Vector2(float(x) / subdivisions.x, float(z + 1) / subdivisions.y)
			var uv11 := Vector2(float(x + 1) / subdivisions.x, float(z + 1) / subdivisions.y)

			# Triangle 1: v00, v10, v01
			var n1 := (v10 - v00).cross(v01 - v00).normalized()
			st.set_normal(n1)
			st.set_uv(uv00)
			st.add_vertex(v00)
			st.set_normal(n1)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_normal(n1)
			st.set_uv(uv01)
			st.add_vertex(v01)

			# Triangle 2: v10, v11, v01
			var n2 := (v11 - v10).cross(v01 - v10).normalized()
			st.set_normal(n2)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_normal(n2)
			st.set_uv(uv11)
			st.add_vertex(v11)
			st.set_normal(n2)
			st.set_uv(uv01)
			st.add_vertex(v01)

	st.index()
	mesh = st.commit()

	# Generate collision shape only at runtime (not in editor)
	if not Engine.is_editor_hint() and get_parent() is StaticBody3D:
		var trimesh := mesh.create_trimesh_shape()
		var col_shape: CollisionShape3D
		for child in get_parent().get_children():
			if child is CollisionShape3D:
				col_shape = child
				break
		if col_shape == null:
			col_shape = CollisionShape3D.new()
			get_parent().add_child(col_shape)
		col_shape.shape = trimesh
		print("Collision shape created: faces=%d" % trimesh.get_faces().size())

	print("Terrain generated: %d x %d verts, size %s" % [verts_x, verts_z, terrain_size])
	if not Engine.is_editor_hint():
		terrain_ready.emit()


## Sample terrain height at a world XZ position using bilinear interpolation
func get_height_at(world_x: float, world_z: float) -> float:
	var total_heights := _base_heights
	if total_heights.size() == 0:
		return 0.0
	var verts_x: int = subdivisions.x + 1
	var verts_z: int = subdivisions.y + 1
	var half_x := terrain_size.x * 0.5
	var half_z := terrain_size.y * 0.5
	var step_x := terrain_size.x / subdivisions.x
	var step_z := terrain_size.y / subdivisions.y

	# Convert world pos to grid coordinates
	var gx := (world_x + half_x) / step_x
	var gz := (world_z + half_z) / step_z
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz

	ix = clampi(ix, 0, subdivisions.x - 1)
	iz = clampi(iz, 0, subdivisions.y - 1)
	var ix1 := mini(ix + 1, subdivisions.x)
	var iz1 := mini(iz + 1, subdivisions.y)

	var h00 := total_heights[iz * verts_x + ix]
	var h10 := total_heights[iz * verts_x + ix1]
	var h01 := total_heights[iz1 * verts_x + ix]
	var h11 := total_heights[iz1 * verts_x + ix1]

	# Add sculpt overlay
	if sculpt_overlay.size() == total_heights.size():
		h00 += sculpt_overlay[iz * verts_x + ix]
		h10 += sculpt_overlay[iz * verts_x + ix1]
		h01 += sculpt_overlay[iz1 * verts_x + ix]
		h11 += sculpt_overlay[iz1 * verts_x + ix1]

	# Bilinear interpolation
	var h0 := lerpf(h00, h10, fx)
	var h1 := lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)


## Called by the sculpt plugin to modify overlay data (fast, no mesh rebuild)
func apply_sculpt(world_pos: Vector3, radius: float, strength: float) -> void:
	var verts_x: int = subdivisions.x + 1
	var verts_z: int = subdivisions.y + 1
	var total := verts_x * verts_z

	# Initialize overlay if needed
	if sculpt_overlay.size() != total:
		sculpt_overlay.resize(total)
		for i in range(total):
			sculpt_overlay[i] = 0.0

	var step_x: float = terrain_size.x / subdivisions.x
	var step_z: float = terrain_size.y / subdivisions.y
	var origin_x: float = -terrain_size.x * 0.5
	var origin_z: float = -terrain_size.y * 0.5

	# Find affected vertices
	var min_xi := maxi(0, int((world_pos.x - radius - origin_x) / step_x))
	var max_xi := mini(verts_x - 1, int((world_pos.x + radius - origin_x) / step_x) + 1)
	var min_zi := maxi(0, int((world_pos.z - radius - origin_z) / step_z))
	var max_zi := mini(verts_z - 1, int((world_pos.z + radius - origin_z) / step_z) + 1)

	for zi in range(min_zi, max_zi + 1):
		for xi in range(min_xi, max_xi + 1):
			var vx := origin_x + xi * step_x
			var vz := origin_z + zi * step_z
			var dist := Vector2(vx, vz).distance_to(Vector2(world_pos.x, world_pos.z))
			if dist < radius:
				var t := 1.0 - (dist / radius)
				t = t * t * (3.0 - 2.0 * t)  # smoothstep
				var idx := zi * verts_x + xi
				sculpt_overlay[idx] += strength * t


## Rebuild mesh using cached base heights + current sculpt overlay (no noise recalc)
func rebuild_mesh_fast() -> void:
	if _base_heights.size() == 0:
		# No cached heights yet, do a full generate
		_generate_terrain()
		return

	var verts_x: int = subdivisions.x + 1
	var verts_z: int = subdivisions.y + 1
	var step_x: float = terrain_size.x / subdivisions.x
	var step_z: float = terrain_size.y / subdivisions.y
	var origin := Vector3(-terrain_size.x * 0.5, 0.0, -terrain_size.y * 0.5)

	# Combine base heights + sculpt overlay
	var heights: Array[float] = []
	heights.resize(_base_heights.size())
	for i in range(_base_heights.size()):
		heights[i] = _base_heights[i]
		if sculpt_overlay.size() == _base_heights.size():
			heights[i] += sculpt_overlay[i]

	# Rebuild mesh triangles
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(subdivisions.y):
		for x in range(subdivisions.x):
			var i00: int = z * verts_x + x
			var i10: int = z * verts_x + x + 1
			var i01: int = (z + 1) * verts_x + x
			var i11: int = (z + 1) * verts_x + x + 1

			var v00 := Vector3(origin.x + x * step_x, heights[i00], origin.z + z * step_z)
			var v10 := Vector3(origin.x + (x + 1) * step_x, heights[i10], origin.z + z * step_z)
			var v01 := Vector3(origin.x + x * step_x, heights[i01], origin.z + (z + 1) * step_z)
			var v11 := Vector3(origin.x + (x + 1) * step_x, heights[i11], origin.z + (z + 1) * step_z)

			var uv00 := Vector2(float(x) / subdivisions.x, float(z) / subdivisions.y)
			var uv10 := Vector2(float(x + 1) / subdivisions.x, float(z) / subdivisions.y)
			var uv01 := Vector2(float(x) / subdivisions.x, float(z + 1) / subdivisions.y)
			var uv11 := Vector2(float(x + 1) / subdivisions.x, float(z + 1) / subdivisions.y)

			var n1 := (v10 - v00).cross(v01 - v00).normalized()
			st.set_normal(n1)
			st.set_uv(uv00)
			st.add_vertex(v00)
			st.set_normal(n1)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_normal(n1)
			st.set_uv(uv01)
			st.add_vertex(v01)

			var n2 := (v11 - v10).cross(v01 - v10).normalized()
			st.set_normal(n2)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_normal(n2)
			st.set_uv(uv11)
			st.add_vertex(v11)
			st.set_normal(n2)
			st.set_uv(uv01)
			st.add_vertex(v01)

	st.index()
	mesh = st.commit()
