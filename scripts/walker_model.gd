@tool
extends Node3D

## Builds the walker character model by loading the base mesh from
## walker.glb and merging walk/run animations from separate GLB files into one
## AnimationPlayer. Sets up an AnimationTree with a BlendSpace1D for smooth
## idle → walk → run transitions driven by speed.
## @tool is safe here: GLB models are external resource references, not baked mesh data.

const IDLE_SCENE := preload("res://Assest/Walker/walker.glb")
const WALK_SCENE := preload("res://Assest/Walker/walker_walk.glb")
const RUN_SCENE := preload("res://Assest/Walker/walker_run.glb")

## Drag this slider in the Inspector to preview animations in the editor.
## 0.0 = idle, 0.5 = walk, 1.0 = run
@export_range(0.0, 1.0, 0.01) var preview_blend: float = 0.0:
	set(value):
		preview_blend = value
		set_movement_blend(value)

var anim_tree: AnimationTree
var _anim_player: AnimationPlayer
var _built := false


func _ready() -> void:
	if _built:
		return
	_setup()


func _setup() -> void:
	# Use existing WalkerMesh if user placed it in the editor, otherwise instantiate
	var mesh_node: Node = get_node_or_null("WalkerMesh")
	if not mesh_node:
		mesh_node = IDLE_SCENE.instantiate()
		mesh_node.name = "WalkerMesh"
		add_child(mesh_node)
		if Engine.is_editor_hint() and get_tree().edited_scene_root:
			mesh_node.owner = get_tree().edited_scene_root

	# Find the AnimationPlayer inside the mesh
	_anim_player = _find_typed(mesh_node, &"AnimationPlayer") as AnimationPlayer
	if not _anim_player:
		push_error("WalkerModel: No AnimationPlayer found in walker model")
		return

	# Get the default animation library
	var lib: AnimationLibrary = _anim_player.get_animation_library(&"")

	# Rename "NlaTrack" → "idle" (only if not already renamed)
	if lib.has_animation(&"NlaTrack"):
		var idle_anim := lib.get_animation(&"NlaTrack")
		idle_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_position_tracks(idle_anim)
		lib.remove_animation(&"NlaTrack")
		lib.add_animation(&"idle", idle_anim)
	elif lib.has_animation(&"idle"):
		_strip_root_position_tracks(lib.get_animation(&"idle"))

	# Import walk animation (always re-import to apply root position stripping)
	if lib.has_animation(&"walk"):
		lib.remove_animation(&"walk")
	_import_animation(WALK_SCENE, &"walk", lib)

	# Import run animation (always re-import to apply root position stripping)
	if lib.has_animation(&"run"):
		lib.remove_animation(&"run")
	_import_animation(RUN_SCENE, &"run", lib)

	_setup_animation_tree()
	_built = true
	print("WalkerModel: Animations loaded: ", _anim_player.get_animation_list())


func _import_animation(scene: PackedScene, anim_name: StringName, target_lib: AnimationLibrary) -> void:
	var instance: Node3D = scene.instantiate()
	add_child(instance)
	var ap: AnimationPlayer = _find_typed(instance, &"AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(&"NlaTrack"):
		var anim: Animation = ap.get_animation(&"NlaTrack").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_position_tracks(anim)
		target_lib.add_animation(anim_name, anim)
	instance.queue_free()


## Remove or flatten position tracks so the character stays in place
## (no root-motion drift from AI-generated animations).
func _strip_root_position_tracks(anim: Animation) -> void:
	print("WalkerModel: Scanning %d tracks for root motion..." % anim.get_track_count())
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(track_idx)
		var path_str := str(path)
		var track_type := anim.track_get_type(track_idx)
		var type_name := "unknown"
		match track_type:
			Animation.TYPE_POSITION_3D: type_name = "POSITION"
			Animation.TYPE_ROTATION_3D: type_name = "ROTATION"
			Animation.TYPE_SCALE_3D: type_name = "SCALE"
			Animation.TYPE_VALUE: type_name = "VALUE"
			Animation.TYPE_BLEND_SHAPE: type_name = "BLEND_SHAPE"
		print("  Track %d: [%s] %s (keys=%d)" % [track_idx, type_name, path_str, anim.track_get_key_count(track_idx)])

		# Flatten Root bone position to ZERO (AI models often have offset even on first frame)
		if track_type == Animation.TYPE_POSITION_3D and path_str.contains("Root"):
			for key_idx in range(anim.track_get_key_count(track_idx)):
				anim.track_set_key_value(track_idx, key_idx, Vector3.ZERO)
			print("    -> ZEROED Root position (%d keys)" % anim.track_get_key_count(track_idx))


func _setup_animation_tree() -> void:
	if not _anim_player:
		return

	# Reuse existing AnimationTree if present (editor reload)
	var existing := get_node_or_null("AnimationTree") as AnimationTree
	if existing:
		anim_tree = existing
		anim_tree.anim_player = _anim_player.get_path()
		anim_tree.active = true
		return

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.anim_player = _anim_player.get_path()
	anim_tree.active = true

	# Create a BlendSpace1D: 0.0 = idle, 0.5 = walk, 1.0 = run
	var blend_space := AnimationNodeBlendSpace1D.new()
	blend_space.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	blend_space.min_space = 0.0
	blend_space.max_space = 1.0

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	blend_space.add_blend_point(idle_node, 0.0)

	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = &"walk"
	blend_space.add_blend_point(walk_node, 0.5)

	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"run"
	blend_space.add_blend_point(run_node, 1.0)

	# Wrap in an AnimationNodeBlendTree so we can set a root
	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node(&"BlendSpace", blend_space, Vector2(0, 0))

	# Connect BlendSpace output to the tree output
	tree_root.connect_node(&"output", 0, &"BlendSpace")

	anim_tree.tree_root = tree_root
	add_child(anim_tree)


## Set blend value: 0.0 = idle, 0.5 = walk, 1.0 = run
func set_movement_blend(value: float) -> void:
	if anim_tree and anim_tree.active:
		anim_tree.set(&"parameters/BlendSpace/blend_position", clampf(value, 0.0, 1.0))


func _find_typed(root: Node, type_name: StringName) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_typed(child, type_name)
		if found:
			return found
	return null
