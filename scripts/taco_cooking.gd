extends Node3D

## 3D Interactive Taco Cooking Mini-Game
## Walk up to taco stand → [E] to enter cooking mode →
## Aim crosshair at real food models → Click to pick ingredients →
## Space to serve → Score displayed on HUD.

signal cooking_started
signal cooking_ended

@export var interact_distance: float = 5.0
@export var raycast_distance: float = 4.0

# ── Ingredient mapping: GLB node name prefix → ingredient id ──
# Only actual food items — no furniture/structure
const NODE_TO_INGREDIENT := {
	"Tortilla_0": "tortilla",
	"Meat_001": "meat_asada",
	"Meat_002": "meat_asada",
	"Meat_003": "meat_pastor",
	"Meat_004": "meat_pastor",
	"Meat_Shepherd": "meat_shepherd",
	"shepherd_spinning": "meat_shepherd",
	"Sauce_001": "salsa_roja",
	"Sauce_01": "salsa_verde",
	"Sauce_02": "salsa_verde",
	"Sauce_03": "salsa_roja",
	"Sauce_04": "salsa_roja",
	"Onion_Coriander": "onion_cilantro",
	"Limon_0": "limon",
	"Plate_Limon": "limon",
	"Salt_": "salt",
	"Sal_": "salt",
	"pepper_": "pepper",
	"Oil_": "oil",
	"Soda_0": "soda",
	"Disposable_cups": "soda",
	"Tacos_": "taco_prepared",
	"Tacos": "taco_prepared",
	"Taco_": "taco_prepared",
}

const INGREDIENT_DISPLAY := {
	"tortilla": "Tortilla",
	"meat_asada": "Carne Asada",
	"meat_pastor": "Al Pastor",
	"meat_shepherd": "Shepherd Meat",
	"salsa_verde": "Salsa Verde",
	"salsa_roja": "Salsa Roja",
	"onion_cilantro": "Onion & Cilantro",
	"limon": "Lime",
	"salt": "Salt",
	"pepper": "Pepper",
	"oil": "Oil",
	"soda": "Soda",
	"taco_prepared": "Prepared Taco",
}

# State
var _is_cooking: bool = false
var _local_player: CharacterBody3D = null
var _selected_ingredients: Array[String] = []
var _aimed_body: StaticBody3D = null
var _ingredient_bodies: Dictionary = {}  # StaticBody3D -> ingredient_id
var _body_to_mesh: Dictionary = {}  # StaticBody3D -> MeshInstance3D
var _ingredient_to_meshes: Dictionary = {}  # ingredient_id -> Array[MeshInstance3D]
var _queue_manager: Node3D = null

# Cinematic intro
var _intro_played: bool = false
var _cinematic: CinematicCamera = null

# Highlight / glow
var _outline_shader: Shader
var _glow_shader: Shader
var _current_outline_mesh: MeshInstance3D = null  # The overlay mesh for aimed item
var _glow_overlays: Array[MeshInstance3D] = []  # Active glow overlays for order hints
var _fly_tweens: Array[Tween] = []  # Active fly animations
var _last_order_name: String = ""  # Track current order to avoid redundant glow updates
var _current_order_reqs: Array = []  # Current order's required ingredients for glow

# UI
var _hud_layer: CanvasLayer
var _prompt_label: Label
var _crosshair: Label
var _aim_label: Label
var _money_label: Label
var _result_label: Label
var _hint_label: Label


func _ready() -> void:
	_outline_shader = load("res://shaders/ingredient_outline.gdshader") as Shader
	_glow_shader = load("res://shaders/ingredient_glow.gdshader") as Shader
	# Wait a frame for the Tacos GLB instance to be fully loaded
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_ingredient_colliders()
	_build_hud()
	_setup_queue_manager()


func _process(_delta: float) -> void:
	# HUD not built yet (waiting for await in _ready)
	if not _prompt_label:
		return

	# Cinematic playing — skip all cooking logic
	if _cinematic and _cinematic.is_playing():
		return

	if not _is_cooking:
		_check_proximity()
		return

	# Update order display from front customer
	_update_front_order()

	# Raycast from camera center
	_do_raycast()


func _unhandled_input(event: InputEvent) -> void:
	# Block input during cinematic
	if _cinematic and _cinematic.is_playing():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if _is_cooking:
				_exit_cooking()
			else:
				_try_enter_cooking()
		elif event.keycode == KEY_SPACE and _is_cooking:
			_serve_taco()
		elif event.keycode == KEY_R and _is_cooking:
			_selected_ingredients.clear()
			_result_label.text = "Cleared"
			_refresh_glow()
			_update_front_customer_bubble()
		elif event.keycode == KEY_ESCAPE and _is_cooking:
			_exit_cooking()

	if event is InputEventMouseButton and event.pressed and _is_cooking:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pick_aimed_ingredient()


# ── Proximity check ──
func _check_proximity() -> void:
	_local_player = _find_local_player()
	var prompt_panel: PanelContainer = _prompt_label.get_meta("panel")
	if not _local_player:
		prompt_panel.visible = false
		return
	var dist := _xz_distance(_local_player.global_position, global_position)
	prompt_panel.visible = dist < interact_distance

	# First-time approach: play cinematic intro
	if not _intro_played and dist < interact_distance:
		_intro_played = true
		_start_intro()


func _try_enter_cooking() -> void:
	_local_player = _find_local_player()
	if not _local_player:
		return
	if _xz_distance(_local_player.global_position, global_position) >= interact_distance:
		return
	_enter_cooking()


# ── Cinematic intro ──
func _start_intro() -> void:
	_local_player = _find_local_player()
	if not _local_player:
		return

	# Find taco stand center
	var look_target := global_position + Vector3(0, 1.0, 0)
	var stand := get_node_or_null("../Tacos/Taco_stand")
	if stand:
		look_target = stand.global_position + Vector3(0, 0.5, 0)

	# Generate 6 random viewpoints around the stand
	var points: Array = []
	for i in range(6):
		# Random angle around the stand
		var angle := randf() * TAU
		# Mix of close (3-5m) and far (6-10m) distances
		var dist := randf_range(3.0, 10.0)
		# Random height between 1.5m and 5m
		var height := randf_range(1.5, 5.0)
		var base_pos := look_target + Vector3(
			cos(angle) * dist, height, sin(angle) * dist
		)
		# Slow drift: small random offset (0.3-0.8m) for gentle movement
		var drift := Vector3(
			randf_range(-0.8, 0.8), randf_range(-0.3, 0.3), randf_range(-0.8, 0.8)
		)
		points.append({"from": base_pos, "to": base_pos + drift})

	# Create and configure CinematicCamera
	_cinematic = CinematicCamera.new()
	add_child(_cinematic)
	_cinematic.play_montage(points, look_target, 5.0, 55.0)

	# Hide prompt during intro
	var prompt_panel: PanelContainer = _prompt_label.get_meta("panel")
	prompt_panel.visible = false


func _enter_cooking() -> void:
	_is_cooking = true
	var prompt_panel: PanelContainer = _prompt_label.get_meta("panel")
	prompt_panel.visible = false
	_crosshair.visible = true
	var aim_panel: PanelContainer = _aim_label.get_meta("panel")
	aim_panel.visible = true
	var hint_panel: PanelContainer = _hint_label.get_meta("panel")
	hint_panel.visible = true
	var money_panel: PanelContainer = _money_label.get_meta("panel")
	money_panel.visible = true
	_selected_ingredients.clear()
	_result_label.text = ""
	_update_money_display()
	if _queue_manager:
		_queue_manager.start_queue()
	cooking_started.emit()


func _exit_cooking() -> void:
	_is_cooking = false
	_crosshair.visible = false
	var aim_panel: PanelContainer = _aim_label.get_meta("panel")
	aim_panel.visible = false
	_aim_label.text = ""
	var hint_panel: PanelContainer = _hint_label.get_meta("panel")
	hint_panel.visible = false
	var money_panel: PanelContainer = _money_label.get_meta("panel")
	money_panel.visible = false
	_result_label.text = ""
	_remove_outline()
	_remove_all_glow()
	_last_order_name = ""
	_current_order_reqs = []
	_aimed_body = null
	if _queue_manager:
		_queue_manager.stop_queue()
	cooking_ended.emit()


# ── Raycast from screen center ──
func _do_raycast() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var center := vp_size / 2.0
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var to := from + dir * raycast_distance

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Only detect cooking collision layer (layer 20)
	query.collision_mask = 1 << 19
	var result := space.intersect_ray(query)

	if result and result.collider is StaticBody3D and result.collider in _ingredient_bodies:
		var new_body: StaticBody3D = result.collider
		if new_body != _aimed_body:
			_remove_outline()
			_aimed_body = new_body
			_add_outline(_body_to_mesh.get(_aimed_body) as MeshInstance3D)
		var ing_id: String = _ingredient_bodies[_aimed_body]
		var display: String = INGREDIENT_DISPLAY.get(ing_id, ing_id)
		_aim_label.text = display
		_aim_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	else:
		if _aimed_body:
			_remove_outline()
		_aimed_body = null
		_aim_label.text = ""


func _pick_aimed_ingredient() -> void:
	if not _aimed_body or _aimed_body not in _ingredient_bodies:
		return
	var ing_id: String = _ingredient_bodies[_aimed_body]
	if ing_id not in _selected_ingredients:
		_selected_ingredients.append(ing_id)
		_result_label.text = "+ " + INGREDIENT_DISPLAY.get(ing_id, ing_id)
		_result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
		# Fly animation: clone mesh toward camera
		var source_mi: MeshInstance3D = _body_to_mesh.get(_aimed_body) as MeshInstance3D
		if source_mi:
			_fly_ingredient_to_camera(source_mi)
		# Refresh glow: already-picked items stop glowing
		_refresh_glow()
		# Update NPC bubble colors
		_update_front_customer_bubble()


# ── Queue-based order system ──
func _setup_queue_manager() -> void:
	_queue_manager = get_node_or_null("../TacoQueueManager")
	if not _queue_manager:
		push_warning("TacoCooking: TacoQueueManager not found, creating one")
		var qm_script := load("res://scripts/taco_queue_manager.gd") as GDScript
		if qm_script:
			_queue_manager = Node3D.new()
			_queue_manager.set_script(qm_script)
			_queue_manager.name = "TacoQueueManager"
			_queue_manager.global_position = global_position
			get_parent().add_child(_queue_manager)
	if _queue_manager:
		_queue_manager.money_changed.connect(_on_money_changed)
		_queue_manager.customer_served.connect(_on_customer_served)
		_queue_manager.customer_lost.connect(_on_customer_lost)


func _serve_taco() -> void:
	if not _queue_manager:
		return
	var result: Dictionary = _queue_manager.serve_front_customer(_selected_ingredients)
	if result.get("success", false):
		_result_label.add_theme_color_override("font_color", Color.GREEN)
		_result_label.text = result.get("message", "Served!")
	else:
		_result_label.add_theme_color_override("font_color", Color.RED)
		_result_label.text = result.get("message", "No customer!")
	_selected_ingredients.clear()
	_last_order_name = ""  # Force order refresh for next customer
	_update_money_display()
	_update_front_customer_bubble()


func _update_front_order() -> void:
	if not _queue_manager:
		_remove_all_glow()
		_last_order_name = ""
		_current_order_reqs = []
		return
	var cur_order: Dictionary = _queue_manager.get_front_order()
	if cur_order.is_empty():
		_remove_all_glow()
		_last_order_name = ""
		_current_order_reqs = []
		return
	# Only refresh glow/bubble when order changes
	var order_key: String = cur_order.get("name", "") + str(cur_order.get("required", []))
	if order_key != _last_order_name:
		_last_order_name = order_key
		_current_order_reqs = cur_order.get("required", [])
		_refresh_glow()
		_update_front_customer_bubble()


func _refresh_glow() -> void:
	# Glow only ingredients that are required but NOT yet picked
	var unpicked: Array = []
	for r in _current_order_reqs:
		if r not in _selected_ingredients:
			unpicked.append(r)
	_add_glow_to_ingredients(unpicked)


func _update_money_display() -> void:
	if not _queue_manager:
		_money_label.text = "$0"
		return
	_money_label.text = "$%d" % _queue_manager._total_money


func _on_money_changed(_total: int) -> void:
	_update_money_display()

func _on_customer_served(_count: int) -> void:
	_update_money_display()

func _on_customer_lost(_count: int) -> void:
	_update_money_display()


func _update_front_customer_bubble() -> void:
	if not _queue_manager:
		return
	var front: Node3D = _queue_manager.get_front_customer()
	if front and front.has_method("update_bubble_colors"):
		front.update_bubble_colors(_selected_ingredients)


# ── Setup colliders on food meshes ──
func _setup_ingredient_colliders() -> void:
	var tacos_node := get_node_or_null("../Tacos")
	if not tacos_node:
		tacos_node = get_node_or_null("/root/TacoMap/Tacos")
	if not tacos_node:
		push_warning("TacoCooking: Could not find Tacos node")
		return

	# Scan all MeshInstance3D children
	var meshes: Array[Node] = []
	_collect_meshes(tacos_node, meshes)

	for mesh_node: Node in meshes:
		var mi := mesh_node as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		var node_name: String = mi.name
		var ing_id := _match_ingredient(node_name)
		if ing_id.is_empty():
			continue

		# Create StaticBody3D + collision on layer 20
		var body := StaticBody3D.new()
		body.collision_layer = 1 << 19
		body.collision_mask = 0
		mi.add_child(body)

		# Use AABB-based BoxShape for simplicity
		var aabb := mi.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size * 1.2  # Slightly larger for easier aiming
		var col := CollisionShape3D.new()
		col.shape = box
		col.position = aabb.get_center()
		body.add_child(col)

		_ingredient_bodies[body] = ing_id
		_body_to_mesh[body] = mi
		if ing_id not in _ingredient_to_meshes:
			_ingredient_to_meshes[ing_id] = []
		_ingredient_to_meshes[ing_id].append(mi)


func _collect_meshes(node: Node, result: Array[Node]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)


func _match_ingredient(node_name: String) -> String:
	for prefix: String in NODE_TO_INGREDIENT:
		if node_name.begins_with(prefix):
			return NODE_TO_INGREDIENT[prefix]
	return ""


# ── Outline highlight (aim) ──
func _add_outline(mi: MeshInstance3D) -> void:
	if not mi or not mi.mesh or not _outline_shader:
		return
	_remove_outline()
	var overlay := MeshInstance3D.new()
	overlay.mesh = mi.mesh
	overlay.material_override = ShaderMaterial.new()
	overlay.material_override.shader = _outline_shader
	overlay.material_override.set_shader_parameter("outline_color", Color(1.0, 1.0, 0.3, 0.9))
	overlay.material_override.set_shader_parameter("outline_width", 0.015)
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(overlay)
	_current_outline_mesh = overlay


func _remove_outline() -> void:
	if is_instance_valid(_current_outline_mesh):
		_current_outline_mesh.queue_free()
	_current_outline_mesh = null


# ── Glow overlay (order hint) ──
func _add_glow_to_ingredients(required: Array) -> void:
	_remove_all_glow()
	for ing_id in required:
		var meshes: Array = _ingredient_to_meshes.get(ing_id, [])
		for mi in meshes:
			if not is_instance_valid(mi) or not mi.mesh:
				continue
			var overlay := MeshInstance3D.new()
			overlay.mesh = mi.mesh
			var mat := ShaderMaterial.new()
			mat.shader = _glow_shader
			mat.set_shader_parameter("glow_color", Color(0.3, 1.0, 0.4, 1.0))
			mat.set_shader_parameter("glow_intensity", 1.5)
			mat.set_shader_parameter("pulse_speed", 2.5)
			mat.render_priority = 1
			overlay.material_override = mat
			overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			overlay.transparency = 0.5
			mi.add_child(overlay)
			_glow_overlays.append(overlay)


func _remove_all_glow() -> void:
	for ov in _glow_overlays:
		if is_instance_valid(ov):
			ov.queue_free()
	_glow_overlays.clear()


# ── Fly ingredient to camera ──
func _fly_ingredient_to_camera(source_mi: MeshInstance3D) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam or not source_mi.mesh:
		return

	# Duplicate the entire MeshInstance3D to preserve materials
	var clone: MeshInstance3D = source_mi.duplicate() as MeshInstance3D
	# Remove any children (colliders etc.) from the clone
	for child in clone.get_children():
		child.queue_free()
	clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Add to scene root so it's independent of parent hierarchy
	get_tree().current_scene.add_child(clone)
	# Set world position to match source
	clone.global_transform = source_mi.global_transform

	# Bright overlay so the flying item stands out
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.9, 0.3)
	mat.emission_energy_multiplier = 3.0
	clone.material_overlay = mat

	# Start position and target (slightly in front of camera)
	var start_pos := clone.global_position
	var target_pos := cam.global_position + cam.global_transform.basis * Vector3(0.0, -0.2, -0.6)
	# Mid point: arc upward
	var mid_pos := (start_pos + target_pos) * 0.5 + Vector3(0, 0.8, 0)

	var start_scale := clone.scale
	var duration := 0.5

	# Phase 1: rise to mid point (0.2s)
	var tween := create_tween()
	tween.tween_property(clone, "global_position", mid_pos, duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Phase 2: fly to camera and shrink (0.3s)
	tween.tween_property(clone, "global_position", target_pos, duration * 0.6) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Parallel: scale down and fade
	var tween2 := create_tween()
	tween2.tween_property(clone, "scale", start_scale * 0.05, duration) \
		.set_ease(Tween.EASE_IN)
	var tween3 := create_tween()
	tween3.tween_property(mat, "albedo_color:a", 0.0, duration) \
		.set_ease(Tween.EASE_IN).set_delay(duration * 0.5)
	# Clean up
	tween.tween_callback(clone.queue_free)


# ── Utility ──
func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _find_local_player() -> CharacterBody3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody3D:
			if not p.multiplayer.has_multiplayer_peer():
				return p
			if p.get_multiplayer_authority() == p.multiplayer.get_unique_id():
				return p
	return null


# ── Build HUD ──
func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 21
	add_child(_hud_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	# ── Center container for prompt / crosshair / aim ──
	var center_box := VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 4)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_box.size = Vector2(300, 120)
	center_box.position = Vector2(-150, -60)
	root.add_child(center_box)

	# [E] Prompt — large, with background for visibility
	var prompt_panel := PanelContainer.new()
	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = Color(0, 0, 0, 0.6)
	prompt_style.corner_radius_top_left = 6
	prompt_style.corner_radius_top_right = 6
	prompt_style.corner_radius_bottom_left = 6
	prompt_style.corner_radius_bottom_right = 6
	prompt_style.content_margin_left = 16
	prompt_style.content_margin_right = 16
	prompt_style.content_margin_top = 8
	prompt_style.content_margin_bottom = 8
	prompt_panel.add_theme_stylebox_override("panel", prompt_style)
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.visible = false
	center_box.add_child(prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.text = "Press [E] to Cook Tacos"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 0.7))
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.add_child(_prompt_label)
	# Store panel ref so we can toggle visibility
	_prompt_label.set_meta("panel", prompt_panel)

	# Crosshair
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.visible = false
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_theme_font_size_override("font_size", 36)
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_crosshair.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_crosshair.add_theme_constant_override("shadow_offset_x", 2)
	_crosshair.add_theme_constant_override("shadow_offset_y", 2)
	center_box.add_child(_crosshair)

	# Aim label (shows ingredient name when aiming at food)
	var aim_panel := PanelContainer.new()
	var aim_style := StyleBoxFlat.new()
	aim_style.bg_color = Color(0, 0, 0, 0.5)
	aim_style.corner_radius_top_left = 4
	aim_style.corner_radius_top_right = 4
	aim_style.corner_radius_bottom_left = 4
	aim_style.corner_radius_bottom_right = 4
	aim_style.content_margin_left = 10
	aim_style.content_margin_right = 10
	aim_style.content_margin_top = 4
	aim_style.content_margin_bottom = 4
	aim_panel.add_theme_stylebox_override("panel", aim_style)
	aim_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_panel.visible = false
	center_box.add_child(aim_panel)

	_aim_label = Label.new()
	_aim_label.text = ""
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_label.add_theme_font_size_override("font_size", 20)
	_aim_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_panel.add_child(_aim_label)
	_aim_label.set_meta("panel", aim_panel)

	# ── Money label (top-right) ──
	var money_panel := PanelContainer.new()
	var money_style := StyleBoxFlat.new()
	money_style.bg_color = Color(0, 0, 0, 0.6)
	money_style.corner_radius_top_left = 8
	money_style.corner_radius_top_right = 8
	money_style.corner_radius_bottom_left = 8
	money_style.corner_radius_bottom_right = 8
	money_style.content_margin_left = 16
	money_style.content_margin_right = 16
	money_style.content_margin_top = 8
	money_style.content_margin_bottom = 8
	money_panel.add_theme_stylebox_override("panel", money_style)
	money_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_panel.visible = false
	root.add_child(money_panel)
	money_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	money_panel.position = Vector2(-140, 16)
	money_panel.size = Vector2(120, 40)

	_money_label = Label.new()
	_money_label.text = "$0"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.add_theme_font_size_override("font_size", 28)
	_money_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	_money_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_money_label.add_theme_constant_override("shadow_offset_x", 2)
	_money_label.add_theme_constant_override("shadow_offset_y", 2)
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_panel.add_child(_money_label)
	_money_label.set_meta("panel", money_panel)

	# ── Result label (center, below crosshair area) ──
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.add_theme_font_size_override("font_size", 20)
	_result_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_result_label.add_theme_constant_override("shadow_offset_x", 1)
	_result_label.add_theme_constant_override("shadow_offset_y", 1)
	center_box.add_child(_result_label)

	# Hint (bottom center with background)
	var hint_panel := PanelContainer.new()
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0, 0, 0, 0.5)
	hint_style.corner_radius_top_left = 6
	hint_style.corner_radius_top_right = 6
	hint_style.corner_radius_bottom_left = 6
	hint_style.corner_radius_bottom_right = 6
	hint_style.content_margin_left = 12
	hint_style.content_margin_right = 12
	hint_style.content_margin_top = 6
	hint_style.content_margin_bottom = 6
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.visible = false
	root.add_child(hint_panel)
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.position = Vector2(-200, -50)
	hint_panel.size = Vector2(400, 30)

	_hint_label = Label.new()
	_hint_label.text = "[Space] Serve | [R] Clear | [E/Esc] Exit"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint_panel.add_child(_hint_label)
	_hint_label.set_meta("panel", hint_panel)
