@tool
extends EditorPlugin

const TERRAIN_SCRIPT_PATH := "res://scripts/terrain_generator.gd"

var _brush_panel: Control
var _active_terrain: Node = null
var _is_sculpting: bool = false
var _brush_radius: float = 8.0
var _brush_strength: float = 0.5
var _brush_mode: int = 0  # 0 = raise, 1 = lower, 2 = smooth
var _sculpt_dirty: bool = false  # True when overlay changed but mesh not rebuilt
var _rebuild_cooldown: float = 0.0  # Time until next allowed rebuild
const REBUILD_INTERVAL := 0.15  # Seconds between mesh rebuilds during sculpt

# Brush indicator
var _brush_indicator: MeshInstance3D
var _brush_indicator_mat: StandardMaterial3D


func _enter_tree() -> void:
	# Create brush settings panel
	_brush_panel = _create_brush_panel()
	_brush_panel.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _brush_panel)

	# Create brush indicator (ring on terrain)
	_brush_indicator = MeshInstance3D.new()
	_brush_indicator_mat = StandardMaterial3D.new()
	_brush_indicator_mat.albedo_color = Color(1, 0.4, 0.1, 0.6)
	_brush_indicator_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_brush_indicator_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brush_indicator_mat.no_depth_test = true
	_brush_indicator.material_override = _brush_indicator_mat
	_brush_indicator.visible = false
	_update_brush_indicator()


func _exit_tree() -> void:
	if _brush_panel:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _brush_panel)
		_brush_panel.queue_free()
		_brush_panel = null
	if _brush_indicator:
		if _brush_indicator.get_parent():
			_brush_indicator.get_parent().remove_child(_brush_indicator)
		_brush_indicator.queue_free()
		_brush_indicator = null


func _handles(object: Object) -> bool:
	# Activate when a MeshInstance3D with terrain_generator.gd is selected
	if object is MeshInstance3D:
		var script = object.get_script()
		if script and script.resource_path == TERRAIN_SCRIPT_PATH:
			return true
	# Also activate when the parent StaticBody3D is selected and has TerrainMesh child
	if object is StaticBody3D:
		for child in object.get_children():
			if child is MeshInstance3D:
				var script = child.get_script()
				if script and script.resource_path == TERRAIN_SCRIPT_PATH:
					return true
	return false


func _edit(object: Object) -> void:
	if object is MeshInstance3D:
		var script = object.get_script()
		if script and script.resource_path == TERRAIN_SCRIPT_PATH:
			_active_terrain = object
	elif object is StaticBody3D:
		for child in object.get_children():
			if child is MeshInstance3D:
				var script = child.get_script()
				if script and script.resource_path == TERRAIN_SCRIPT_PATH:
					_active_terrain = child
					break

	if _active_terrain:
		_brush_panel.visible = true
		# Add brush indicator to the scene
		if _brush_indicator and not _brush_indicator.get_parent():
			_active_terrain.get_parent().add_child(_brush_indicator)
		_brush_indicator.visible = false
		print("Terrain Sculpt: Editing terrain - LMB=Raise, Shift+LMB=Lower")
	else:
		_brush_panel.visible = false
		if _brush_indicator:
			_brush_indicator.visible = false


func _make_visible(visible: bool) -> void:
	if _brush_panel:
		_brush_panel.visible = visible
	if not visible:
		_active_terrain = null
		_is_sculpting = false
		if _brush_indicator:
			_brush_indicator.visible = false
			if _brush_indicator.get_parent():
				_brush_indicator.get_parent().remove_child(_brush_indicator)


func _process(delta: float) -> void:
	if _rebuild_cooldown > 0:
		_rebuild_cooldown -= delta
	# If we have pending sculpt changes and cooldown expired, rebuild
	if _sculpt_dirty and _rebuild_cooldown <= 0 and _active_terrain:
		_sculpt_dirty = false
		_rebuild_cooldown = REBUILD_INTERVAL
		if _active_terrain.has_method("rebuild_mesh_fast"):
			_active_terrain.rebuild_mesh_fast()


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _active_terrain:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var hit := _raycast_terrain(viewport_camera, event.position)
		if hit.size() > 0:
			_brush_indicator.visible = true
			_brush_indicator.global_position = hit.position
			if _is_sculpting:
				_do_sculpt(hit.position)
				return AFTER_GUI_INPUT_STOP
		else:
			_brush_indicator.visible = false
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _raycast_terrain(viewport_camera, event.position)
				if hit.size() > 0:
					_is_sculpting = true
					_do_sculpt(hit.position)
					return AFTER_GUI_INPUT_STOP
			else:
				if _is_sculpting:
					_is_sculpting = false
					# Final rebuild on release
					if _active_terrain.has_method("rebuild_mesh_fast"):
						_active_terrain.rebuild_mesh_fast()
					_sculpt_dirty = false
					return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _do_sculpt(world_pos: Vector3) -> void:
	if not _active_terrain or not _active_terrain.has_method("apply_sculpt"):
		return

	var strength := _brush_strength * 0.15  # Scale down for per-frame application
	if Input.is_key_pressed(KEY_SHIFT):
		strength = -strength

	_active_terrain.apply_sculpt(world_pos, _brush_radius, strength)
	_sculpt_dirty = true


func _raycast_terrain(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var to := from + dir * 1000.0

	var space_state := camera.get_world_3d().direct_space_state
	if not space_state:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, to)
	# In editor, terrain might not have physics collision, so use mesh-based raycast
	# Try physics first
	var result := space_state.intersect_ray(query)
	if result.size() > 0:
		return result

	# Fallback: approximate hit by intersecting with Y=0 plane
	if dir.y != 0:
		var t := -from.y / dir.y
		if t > 0:
			var hit_pos := from + dir * t
			# Check if within terrain bounds
			var half: Vector2 = _active_terrain.terrain_size * 0.5
			if absf(hit_pos.x) <= half.x and absf(hit_pos.z) <= half.y:
				return {"position": hit_pos}

	return {}


func _update_brush_indicator() -> void:
	if not _brush_indicator:
		return
	# Create a torus/ring mesh
	var im := ImmediateMesh.new()
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segments := 48
	for i in range(segments + 1):
		var angle := float(i) / segments * TAU
		var x := cos(angle) * _brush_radius
		var z := sin(angle) * _brush_radius
		im.surface_add_vertex(Vector3(x, 0.5, z))
	im.surface_end()
	_brush_indicator.mesh = im


func _create_brush_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)

	var title := Label.new()
	title.text = "🏔 Terrain Sculpt"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var sep := HSeparator.new()
	panel.add_child(sep)

	# Mode info
	var mode_label := Label.new()
	mode_label.text = "LMB: Raise | Shift+LMB: Lower"
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(mode_label)

	var sep2 := HSeparator.new()
	panel.add_child(sep2)

	# Brush radius
	var radius_label := Label.new()
	radius_label.text = "Brush Radius: 8.0"
	panel.add_child(radius_label)

	var radius_slider := HSlider.new()
	radius_slider.min_value = 1.0
	radius_slider.max_value = 40.0
	radius_slider.step = 0.5
	radius_slider.value = _brush_radius
	radius_slider.value_changed.connect(func(val: float):
		_brush_radius = val
		radius_label.text = "Brush Radius: %.1f" % val
		_update_brush_indicator()
	)
	panel.add_child(radius_slider)

	# Brush strength
	var strength_label := Label.new()
	strength_label.text = "Brush Strength: 0.5"
	panel.add_child(strength_label)

	var strength_slider := HSlider.new()
	strength_slider.min_value = 0.05
	strength_slider.max_value = 3.0
	strength_slider.step = 0.05
	strength_slider.value = _brush_strength
	strength_slider.value_changed.connect(func(val: float):
		_brush_strength = val
		strength_label.text = "Brush Strength: %.2f" % val
	)
	panel.add_child(strength_slider)

	return panel
