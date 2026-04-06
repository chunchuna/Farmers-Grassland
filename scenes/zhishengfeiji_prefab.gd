@tool
extends StaticBody3D

## Auto-generated prefab with merged animations.
## Supports editor preview (@tool) and runtime animation blending.
## Drag this .tscn into your scene to use it.

@export_group("Physics & Collision")
@export var collision_enabled := true:
	set(val):
		collision_enabled = val
		_update_collision()

const ANIM_IDLE := preload("res://Assest/ZhiShengFeiJi/ZhiShengFeiJi.glb")

var anim_tree: AnimationTree
var _anim_player: AnimationPlayer
var _collision_shape: CollisionShape3D
var _built := false


func _ready() -> void:
	if _built:
		return
	_build_model()
	_setup_animation_tree()
	_setup_collision()


func _build_model() -> void:
	# Find existing Model child or instantiate new one
	var existing := get_node_or_null("Model")
	if existing:
		_anim_player = _find_typed(existing, &"AnimationPlayer") as AnimationPlayer
		if _anim_player:
			var lib: AnimationLibrary = _anim_player.get_animation_library(&"")
			_rename_and_import_anims(lib)
			_built = true
			return

	var base_instance := ANIM_IDLE.instantiate()
	base_instance.name = "Model"
	add_child(base_instance)
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		base_instance.owner = get_tree().edited_scene_root

	_anim_player = _find_typed(base_instance, &"AnimationPlayer") as AnimationPlayer
	if not _anim_player:
		push_error("Prefab: No AnimationPlayer found")
		return

	var lib: AnimationLibrary = _anim_player.get_animation_library(&"")
	_rename_and_import_anims(lib)
	_built = true
	print("Prefab: Animations loaded: ", _anim_player.get_animation_list())


func _rename_and_import_anims(lib: AnimationLibrary) -> void:
	if lib.has_animation(&"NlaTrack"):
		var anim := lib.get_animation(&"NlaTrack")
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.remove_animation(&"NlaTrack")
		lib.add_animation(&"idle", anim)


func _import_anim(scene: PackedScene, anim_name: StringName, target_lib: AnimationLibrary) -> void:
	var instance := scene.instantiate()
	add_child(instance)
	var ap := _find_typed(instance, &"AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(&"NlaTrack"):
		var anim := ap.get_animation(&"NlaTrack").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		target_lib.add_animation(anim_name, anim)
	instance.queue_free()


func _setup_collision() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not _collision_shape:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		# Auto-generate collision from model AABB
		var aabb := _get_model_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		_collision_shape.shape = box
		_collision_shape.position = aabb.position + aabb.size * 0.5
		add_child(_collision_shape)
		if Engine.is_editor_hint() and get_tree().edited_scene_root:
			_collision_shape.owner = get_tree().edited_scene_root
	_update_collision()


func _update_collision() -> void:
	if _collision_shape:
		_collision_shape.disabled = not collision_enabled


func _get_model_aabb() -> AABB:
	var model := get_node_or_null("Model")
	if not model:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	var result := AABB()
	var first := true
	for child in _get_all_children(model):
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			var mesh_aabb: AABB = mi.get_aabb()
			var t: Transform3D = mi.global_transform * Transform3D(Basis(), mesh_aabb.position)
			var local_pos: Vector3 = global_transform.affine_inverse() * t.origin
			var local_aabb: AABB = AABB(local_pos, mesh_aabb.size)
			if first:
				result = local_aabb
				first = false
			else:
				result = result.merge(local_aabb)
	if first:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	return result


func _get_all_children(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_children(child))
	return result


func _setup_animation_tree() -> void:
	if not _anim_player:
		return

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.anim_player = _anim_player.get_path()
	anim_tree.active = true

	var anim_node := AnimationNodeAnimation.new()
	anim_node.animation = &"idle"
	anim_tree.tree_root = anim_node
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
