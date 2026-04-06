@tool
extends VBoxContainer

## Editor dock that scans a folder of GLB files, detects animations,
## and generates a ready-to-use prefab scene with merged AnimationPlayer,
## optional collision body, optional physics, and @export toggles.

var editor_plugin = null  # Set by plugin.gd after instantiation

# Known animation name patterns (filename contains → animation name)
const ANIM_PATTERNS := {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"sprint": "run",
	"jump": "jump",
	"attack": "attack",
	"die": "die",
	"death": "die",
}

var _glb_files: Array[Dictionary] = []  # [{path, anim_name}]
var _base_glb: String = ""  # The main model GLB (idle or base)


func _ready() -> void:
	$FolderRow/BrowseBtn.pressed.connect(_on_browse)
	$FolderRow/FolderPath.text_submitted.connect(_on_folder_entered)
	$GenerateBtn.pressed.connect(_on_generate)
	# Physics implies collision
	$PhysicsCheck.toggled.connect(func(on: bool):
		if on:
			$CollisionCheck.button_pressed = true
			$CollisionCheck.disabled = true
		else:
			$CollisionCheck.disabled = false
	)


func _on_browse() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Select GLB Folder"
	dialog.dir_selected.connect(func(dir: String):
		$FolderRow/FolderPath.text = dir
		_scan_folder(dir)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_folder_entered(path: String) -> void:
	_scan_folder(path)


func _scan_folder(folder_path: String) -> void:
	_glb_files.clear()
	_base_glb = ""
	$AnimList.clear()

	var dir := DirAccess.open(folder_path)
	if not dir:
		_set_status("[color=red]Cannot open folder: %s[/color]" % folder_path)
		return

	# Collect all .glb files
	var glb_paths: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "glb":
			glb_paths.append(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	if glb_paths.is_empty():
		_set_status("[color=red]No .glb files found in %s[/color]" % folder_path)
		return

	# Sort: shorter names first (base model tends to have shortest name)
	glb_paths.sort_custom(func(a: String, b: String): return a.get_file().length() < b.get_file().length())

	# Detect animation names from filenames
	for glb_path in glb_paths:
		var base_name := glb_path.get_file().get_basename().to_lower()
		var anim_name := _detect_anim_name(base_name)
		_glb_files.append({"path": glb_path, "anim_name": anim_name})
		$AnimList.add_item("%s → %s" % [glb_path.get_file(), anim_name])

	# First file with "idle" or shortest name = base model
	_base_glb = _glb_files[0]["path"]
	for entry in _glb_files:
		if entry["anim_name"] == "idle":
			_base_glb = entry["path"]
			break

	# Auto-fill output path
	var char_name := folder_path.get_file().to_lower()
	$OutputPath.text = "res://scenes/%s_prefab.tscn" % char_name

	_set_status("[color=green]Found %d GLB files. Base model: %s[/color]" % [
		_glb_files.size(), _base_glb.get_file()])


func _detect_anim_name(base_name: String) -> String:
	for pattern in ANIM_PATTERNS:
		if base_name.contains(pattern):
			return ANIM_PATTERNS[pattern]
	return "idle"  # Default: treat as idle/base


func _on_generate() -> void:
	if _glb_files.is_empty():
		_set_status("[color=red]No GLB files scanned. Select a folder first.[/color]")
		return

	var output_path: String = $OutputPath.text.strip_edges()
	if output_path.is_empty():
		_set_status("[color=red]Please specify an output scene path.[/color]")
		return

	var want_collision: bool = $CollisionCheck.button_pressed
	var want_physics: bool = $PhysicsCheck.button_pressed
	var model_scale: float = $ScaleRow/ScaleSpinBox.value

	_set_status("Generating prefab...")

	# Generate the @tool script
	var script_path := output_path.get_basename() + ".gd"
	_generate_character_script(script_path, want_collision, want_physics)

	# Generate the .tscn scene file
	_generate_character_scene(output_path, script_path, want_collision, want_physics, model_scale)

	_set_status("[color=green]Done! Created:\n• %s\n• %s\n\nDrag the .tscn into your scene to use it.\nSelect the node to adjust collision/physics in Inspector.[/color]" % [
		output_path, script_path])

	# Refresh filesystem
	EditorInterface.get_resource_filesystem().scan()


func _generate_character_script(script_path: String, want_collision: bool, want_physics: bool) -> void:
	var lines: PackedStringArray = []

	# Determine base type
	var base_type := "Node3D"
	if want_physics:
		base_type = "RigidBody3D"
	elif want_collision:
		base_type = "StaticBody3D"

	lines.append("@tool")
	lines.append("extends %s" % base_type)
	lines.append("")
	lines.append("## Auto-generated prefab with merged animations.")
	lines.append("## Supports editor preview (@tool) and runtime animation blending.")
	lines.append("## Drag this .tscn into your scene to use it.")
	lines.append("")

	# @export toggles for collision and physics
	if want_collision or want_physics:
		lines.append("@export_group(\"Physics & Collision\")")
		lines.append("@export var collision_enabled := true:")
		lines.append("\tset(val):")
		lines.append("\t\tcollision_enabled = val")
		lines.append("\t\t_update_collision()")
		lines.append("")
		if want_physics:
			lines.append("@export var physics_enabled := true:")
			lines.append("\tset(val):")
			lines.append("\t\tphysics_enabled = val")
			lines.append("\t\t_update_physics()")
			lines.append("")

	# Preload lines
	for entry in _glb_files:
		var var_name := "ANIM_%s" % entry["anim_name"].to_upper()
		lines.append('const %s := preload("%s")' % [var_name, entry["path"]])
	lines.append("")

	lines.append("var anim_tree: AnimationTree")
	lines.append("var _anim_player: AnimationPlayer")
	lines.append("var _collision_shape: CollisionShape3D")
	lines.append("var _built := false")
	lines.append("")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tif _built:")
	lines.append("\t\treturn")
	lines.append("\t_build_model()")
	lines.append("\t_setup_animation_tree()")
	if want_collision or want_physics:
		lines.append("\t_setup_collision()")
	lines.append("")
	lines.append("")

	# Build model function
	lines.append("func _build_model() -> void:")
	lines.append("\t# Find existing Model child or instantiate new one")
	lines.append('\tvar existing := get_node_or_null("Model")')
	lines.append("\tif existing:")
	lines.append("\t\t_anim_player = _find_typed(existing, &\"AnimationPlayer\") as AnimationPlayer")
	lines.append("\t\tif _anim_player:")
	lines.append("\t\t\tvar lib: AnimationLibrary = _anim_player.get_animation_library(&\"\")")
	lines.append("\t\t\t_rename_and_import_anims(lib)")
	lines.append("\t\t\t_built = true")
	lines.append("\t\t\treturn")
	lines.append("")

	# Instance base model
	var base_var := "ANIM_%s" % _glb_files[0]["anim_name"].to_upper()
	for entry in _glb_files:
		if entry["path"] == _base_glb:
			base_var = "ANIM_%s" % entry["anim_name"].to_upper()
			break

	lines.append('\tvar base_instance := %s.instantiate()' % base_var)
	lines.append('\tbase_instance.name = "Model"')
	lines.append("\tadd_child(base_instance)")
	lines.append("\tif Engine.is_editor_hint() and get_tree().edited_scene_root:")
	lines.append("\t\tbase_instance.owner = get_tree().edited_scene_root")
	lines.append("")
	lines.append("\t_anim_player = _find_typed(base_instance, &\"AnimationPlayer\") as AnimationPlayer")
	lines.append("\tif not _anim_player:")
	lines.append('\t\tpush_error("Prefab: No AnimationPlayer found")')
	lines.append("\t\treturn")
	lines.append("")
	lines.append("\tvar lib: AnimationLibrary = _anim_player.get_animation_library(&\"\")")
	lines.append("\t_rename_and_import_anims(lib)")
	lines.append("\t_built = true")
	lines.append('\tprint("Prefab: Animations loaded: ", _anim_player.get_animation_list())')
	lines.append("")
	lines.append("")

	# Rename and import animations helper
	lines.append("func _rename_and_import_anims(lib: AnimationLibrary) -> void:")
	# Rename base animation
	for entry in _glb_files:
		if entry["path"] == _base_glb:
			lines.append('\tif lib.has_animation(&"NlaTrack"):')
			lines.append('\t\tvar anim := lib.get_animation(&"NlaTrack")')
			lines.append("\t\tanim.loop_mode = Animation.LOOP_LINEAR")
			lines.append('\t\tlib.remove_animation(&"NlaTrack")')
			lines.append('\t\tlib.add_animation(&"%s", anim)' % entry["anim_name"])
			break
	# Import other animations
	for entry in _glb_files:
		if entry["path"] == _base_glb:
			continue
		var var_name := "ANIM_%s" % entry["anim_name"].to_upper()
		lines.append('\tif not lib.has_animation(&"%s"):' % entry["anim_name"])
		lines.append('\t\t_import_anim(%s, &"%s", lib)' % [var_name, entry["anim_name"]])
	lines.append("")
	lines.append("")

	# Import helper
	lines.append("func _import_anim(scene: PackedScene, anim_name: StringName, target_lib: AnimationLibrary) -> void:")
	lines.append("\tvar instance := scene.instantiate()")
	lines.append("\tadd_child(instance)")
	lines.append('\tvar ap := _find_typed(instance, &"AnimationPlayer") as AnimationPlayer')
	lines.append('\tif ap and ap.has_animation(&"NlaTrack"):')
	lines.append('\t\tvar anim := ap.get_animation(&"NlaTrack").duplicate()')
	lines.append("\t\tanim.loop_mode = Animation.LOOP_LINEAR")
	lines.append("\t\ttarget_lib.add_animation(anim_name, anim)")
	lines.append("\tinstance.queue_free()")
	lines.append("")
	lines.append("")

	# Collision setup
	if want_collision or want_physics:
		lines.append("func _setup_collision() -> void:")
		lines.append('\t_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D')
		lines.append("\tif not _collision_shape:")
		lines.append("\t\t_collision_shape = CollisionShape3D.new()")
		lines.append('\t\t_collision_shape.name = "CollisionShape3D"')
		lines.append("\t\t# Auto-generate collision from model AABB")
		lines.append("\t\tvar aabb := _get_model_aabb()")
		lines.append("\t\tvar box := BoxShape3D.new()")
		lines.append("\t\tbox.size = aabb.size")
		lines.append("\t\t_collision_shape.shape = box")
		lines.append("\t\t_collision_shape.position = aabb.position + aabb.size * 0.5")
		lines.append("\t\tadd_child(_collision_shape)")
		lines.append("\t\tif Engine.is_editor_hint() and get_tree().edited_scene_root:")
		lines.append("\t\t\t_collision_shape.owner = get_tree().edited_scene_root")
		lines.append("\t_update_collision()")
		if want_physics:
			lines.append("\t_update_physics()")
		lines.append("")
		lines.append("")

		lines.append("func _update_collision() -> void:")
		lines.append("\tif _collision_shape:")
		lines.append("\t\t_collision_shape.disabled = not collision_enabled")
		lines.append("")
		lines.append("")

		if want_physics:
			lines.append("func _update_physics() -> void:")
			lines.append("\tif not Engine.is_editor_hint():")
			lines.append("\t\tfreeze = not physics_enabled")
			lines.append("")
			lines.append("")

		lines.append("func _get_model_aabb() -> AABB:")
		lines.append('\tvar model := get_node_or_null("Model")')
		lines.append("\tif not model:")
		lines.append("\t\treturn AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))")
		lines.append("\tvar result := AABB()")
		lines.append("\tvar first := true")
		lines.append("\tfor child in _get_all_children(model):")
		lines.append("\t\tif child is MeshInstance3D:")
		lines.append("\t\t\tvar mesh_aabb := child.get_aabb()")
		lines.append("\t\t\tvar t := child.global_transform * Transform3D(Basis(), mesh_aabb.position)")
		lines.append("\t\t\tvar local_pos := global_transform.affine_inverse() * t.origin")
		lines.append("\t\t\tvar local_aabb := AABB(local_pos, mesh_aabb.size)")
		lines.append("\t\t\tif first:")
		lines.append("\t\t\t\tresult = local_aabb")
		lines.append("\t\t\t\tfirst = false")
		lines.append("\t\t\telse:")
		lines.append("\t\t\t\tresult = result.merge(local_aabb)")
		lines.append("\tif first:")
		lines.append("\t\treturn AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))")
		lines.append("\treturn result")
		lines.append("")
		lines.append("")

		lines.append("func _get_all_children(node: Node) -> Array[Node]:")
		lines.append("\tvar result: Array[Node] = []")
		lines.append("\tfor child in node.get_children():")
		lines.append("\t\tresult.append(child)")
		lines.append("\t\tresult.append_array(_get_all_children(child))")
		lines.append("\treturn result")
		lines.append("")
		lines.append("")

	# Animation tree setup
	lines.append("func _setup_animation_tree() -> void:")
	lines.append("\tif not _anim_player:")
	lines.append("\t\treturn")
	lines.append("")
	lines.append("\tanim_tree = AnimationTree.new()")
	lines.append('\tanim_tree.name = "AnimationTree"')
	lines.append("\tanim_tree.anim_player = _anim_player.get_path()")
	lines.append("\tanim_tree.active = true")
	lines.append("")

	# Collect unique animation names
	var anim_names: Array[String] = []
	for entry in _glb_files:
		if entry["anim_name"] not in anim_names:
			anim_names.append(entry["anim_name"])

	# If we have idle/walk/run, use BlendSpace1D
	var has_locomotion := "idle" in anim_names and ("walk" in anim_names or "run" in anim_names)

	if has_locomotion:
		lines.append("\t# BlendSpace1D: 0.0=idle, 0.5=walk, 1.0=run")
		lines.append("\tvar blend_space := AnimationNodeBlendSpace1D.new()")
		lines.append("\tblend_space.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED")
		lines.append("\tblend_space.min_space = 0.0")
		lines.append("\tblend_space.max_space = 1.0")
		lines.append("")

		if "idle" in anim_names:
			lines.append("\tvar idle_node := AnimationNodeAnimation.new()")
			lines.append('\tidle_node.animation = &"idle"')
			lines.append("\tblend_space.add_blend_point(idle_node, 0.0)")
		if "walk" in anim_names:
			lines.append("\tvar walk_node := AnimationNodeAnimation.new()")
			lines.append('\twalk_node.animation = &"walk"')
			lines.append("\tblend_space.add_blend_point(walk_node, 0.5)")
		if "run" in anim_names:
			lines.append("\tvar run_node := AnimationNodeAnimation.new()")
			lines.append('\trun_node.animation = &"run"')
			lines.append("\tblend_space.add_blend_point(run_node, 1.0)")

		lines.append("")
		lines.append("\tvar tree_root := AnimationNodeBlendTree.new()")
		lines.append('\ttree_root.add_node(&"BlendSpace", blend_space, Vector2.ZERO)')
		lines.append('\ttree_root.connect_node(&"output", 0, &"BlendSpace")')
		lines.append("\tanim_tree.tree_root = tree_root")
	else:
		# Simple: just play first animation
		lines.append("\tvar anim_node := AnimationNodeAnimation.new()")
		lines.append('\tanim_node.animation = &"%s"' % anim_names[0])
		lines.append("\tanim_tree.tree_root = anim_node")

	lines.append("\tadd_child(anim_tree)")
	lines.append("")
	lines.append("")

	# Public API
	lines.append("## Set blend value: 0.0 = idle, 0.5 = walk, 1.0 = run")
	lines.append("func set_movement_blend(value: float) -> void:")
	lines.append("\tif anim_tree and anim_tree.active:")
	lines.append('\t\tanim_tree.set(&"parameters/BlendSpace/blend_position", clampf(value, 0.0, 1.0))')
	lines.append("")
	lines.append("")

	# Utility
	lines.append("func _find_typed(root: Node, type_name: StringName) -> Node:")
	lines.append("\tfor child in root.get_children():")
	lines.append("\t\tif child.get_class() == type_name:")
	lines.append("\t\t\treturn child")
	lines.append("\t\tvar found := _find_typed(child, type_name)")
	lines.append("\t\tif found:")
	lines.append("\t\t\treturn found")
	lines.append("\treturn null")
	lines.append("")

	# Write file
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("ModelImporter: Generated script: %s" % script_path)


func _generate_character_scene(scene_path: String, script_path: String, want_collision: bool, want_physics: bool, model_scale: float) -> void:
	# Determine root node type
	var node_type := "Node3D"
	if want_physics:
		node_type = "RigidBody3D"
	elif want_collision:
		node_type = "StaticBody3D"

	var node_name := scene_path.get_file().get_basename().to_pascal_case()
	var scale_str := "Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, 0)" % [model_scale, model_scale, model_scale]

	var content := '[gd_scene format=3]\n\n'
	content += '[ext_resource type="Script" path="%s" id="1_script"]\n' % script_path
	content += '[ext_resource type="PackedScene" path="%s" id="2_model"]\n\n' % _base_glb

	# Collision shape sub-resource (placeholder, will be auto-sized at runtime)
	if want_collision or want_physics:
		content += '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]\n'
		content += 'size = Vector3(1, 1, 1)\n\n'

	content += '[node name="%s" type="%s"]\n' % [node_name, node_type]
	if model_scale != 1.0:
		content += 'transform = %s\n' % scale_str
	content += 'script = ExtResource("1_script")\n'
	if want_physics:
		content += '\n'

	# Collision shape node
	if want_collision or want_physics:
		content += '\n[node name="CollisionShape3D" type="CollisionShape3D" parent="."]\n'
		content += 'shape = SubResource("BoxShape3D_1")\n'

	# Model instance
	content += '\n[node name="Model" type="Node3D" parent="." instance=ExtResource("2_model")]\n'

	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	print("ModelImporter: Generated scene: %s (%s, scale=%.1f)" % [scene_path, node_type, model_scale])


func _set_status(text: String) -> void:
	$StatusLabel.text = text
