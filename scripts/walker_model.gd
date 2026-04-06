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

var anim_tree: AnimationTree
var _anim_player: AnimationPlayer
var _built := false


func _ready() -> void:
	if _built:
		return
	# Clear any leftover children from previous editor reload
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_model()
	_setup_animation_tree()


func _build_model() -> void:
	# Instance the idle/base model (contains mesh + skeleton + idle animation)
	var idle_instance: Node3D = IDLE_SCENE.instantiate()
	idle_instance.name = "WalkerMesh"
	add_child(idle_instance)
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		idle_instance.owner = get_tree().edited_scene_root

	# Find the AnimationPlayer
	_anim_player = _find_typed(idle_instance, &"AnimationPlayer") as AnimationPlayer
	if not _anim_player:
		push_error("WalkerModel: No AnimationPlayer found in walker.glb")
		return

	# Get the default animation library
	var lib: AnimationLibrary = _anim_player.get_animation_library(&"")

	# Rename "NlaTrack" → "idle"
	if lib.has_animation(&"NlaTrack"):
		var idle_anim := lib.get_animation(&"NlaTrack")
		idle_anim.loop_mode = Animation.LOOP_LINEAR
		lib.remove_animation(&"NlaTrack")
		lib.add_animation(&"idle", idle_anim)

	# Import walk animation
	_import_animation(WALK_SCENE, &"walk", lib)

	# Import run animation
	_import_animation(RUN_SCENE, &"run", lib)

	_built = true
	print("WalkerModel: Animations loaded: ", _anim_player.get_animation_list())


func _import_animation(scene: PackedScene, anim_name: StringName, target_lib: AnimationLibrary) -> void:
	var instance: Node3D = scene.instantiate()
	add_child(instance)
	var ap: AnimationPlayer = _find_typed(instance, &"AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(&"NlaTrack"):
		var anim: Animation = ap.get_animation(&"NlaTrack").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		target_lib.add_animation(anim_name, anim)
	instance.queue_free()


func _setup_animation_tree() -> void:
	if not _anim_player:
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
