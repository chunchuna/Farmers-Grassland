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
const NODE_TO_INGREDIENT := {
	"Tortilla": "tortilla",
	"Meat.001": "meat_asada",
	"Meat.002": "meat_asada",
	"Meat.003": "meat_pastor",
	"Meat.004": "meat_pastor",
	"Meat_Shepherd": "meat_shepherd",
	"shepherd_spinning": "meat_shepherd",
	"Sauce.": "salsa_roja",
	"Sauce_01": "salsa_verde",
	"Sauce_02": "salsa_verde",
	"Sauce_03": "salsa_roja",
	"Sauce_04": "salsa_roja",
	"Onion_Coriander": "onion_cilantro",
	"Limon": "limon",
	"Limon_01": "limon",
	"Plate_Limon": "limon",
	"Salt.": "salt",
	"Sal.": "salt",
	"pepper.": "pepper",
	"Oil.": "oil",
	"Soda": "soda",
	"Disposable_cups": "soda",
	"Grill": "grill",
	"Tacos.": "taco_prepared",
	"Taco.": "taco_prepared",
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
	"grill": "Grill",
	"taco_prepared": "Prepared Taco",
}

# State
var _is_cooking: bool = false
var _local_player: CharacterBody3D = null
var _selected_ingredients: Array[String] = []
var _aimed_body: StaticBody3D = null
var _ingredient_bodies: Dictionary = {}  # StaticBody3D -> ingredient_id
var _queue_manager: Node3D = null

# UI
var _hud_layer: CanvasLayer
var _prompt_label: Label
var _crosshair: Label
var _aim_label: Label
var _order_panel: PanelContainer
var _order_label: RichTextLabel
var _picked_label: RichTextLabel
var _money_label: Label
var _stats_label: Label
var _result_label: Label
var _hint_label: Label


func _ready() -> void:
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

	if not _is_cooking:
		_check_proximity()
		return

	# Update order display from front customer
	_update_front_order()

	# Raycast from camera center
	_do_raycast()


func _unhandled_input(event: InputEvent) -> void:
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
			_update_picked_display()
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


func _try_enter_cooking() -> void:
	_local_player = _find_local_player()
	if not _local_player:
		return
	if _xz_distance(_local_player.global_position, global_position) >= interact_distance:
		return
	_enter_cooking()


func _enter_cooking() -> void:
	_is_cooking = true
	var prompt_panel: PanelContainer = _prompt_label.get_meta("panel")
	prompt_panel.visible = false
	_order_panel.visible = true
	_crosshair.visible = true
	var aim_panel: PanelContainer = _aim_label.get_meta("panel")
	aim_panel.visible = true
	var hint_panel: PanelContainer = _hint_label.get_meta("panel")
	hint_panel.visible = true
	_selected_ingredients.clear()
	_update_picked_display()
	_update_money_display()
	_result_label.text = ""
	if _queue_manager:
		_queue_manager.start_queue()
	cooking_started.emit()


func _exit_cooking() -> void:
	_is_cooking = false
	_order_panel.visible = false
	_crosshair.visible = false
	var aim_panel: PanelContainer = _aim_label.get_meta("panel")
	aim_panel.visible = false
	_aim_label.text = ""
	var hint_panel: PanelContainer = _hint_label.get_meta("panel")
	hint_panel.visible = false
	_result_label.text = ""
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
		_aimed_body = result.collider
		var ing_id: String = _ingredient_bodies[_aimed_body]
		var display: String = INGREDIENT_DISPLAY.get(ing_id, ing_id)
		_aim_label.text = display
		_aim_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	else:
		_aimed_body = null
		_aim_label.text = ""


func _pick_aimed_ingredient() -> void:
	if not _aimed_body or _aimed_body not in _ingredient_bodies:
		return
	var ing_id: String = _ingredient_bodies[_aimed_body]
	if ing_id == "grill" or ing_id == "taco_prepared":
		# Can't pick these directly
		_result_label.text = "Can't pick that!"
		return
	if ing_id not in _selected_ingredients:
		_selected_ingredients.append(ing_id)
		_update_picked_display()
		_result_label.text = "+ " + INGREDIENT_DISPLAY.get(ing_id, ing_id)


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
	_update_picked_display()
	_update_money_display()


func _update_front_order() -> void:
	if not _queue_manager:
		_order_label.text = "[color=gray]Waiting for customers...[/color]"
		return
	var order: Dictionary = _queue_manager.get_front_order()
	if order.is_empty():
		_order_label.text = "[color=gray]Waiting for customers...[/color]"
		return
	var text := "[b][color=yellow]ORDER: %s[/color][/b]\n" % order.get("name", "Taco")
	text += "[color=white]Need:[/color] "
	var reqs: Array = order.get("required", [])
	var req_names: Array[String] = []
	for r in reqs:
		req_names.append(INGREDIENT_DISPLAY.get(r, r))
	text += ", ".join(req_names)
	var bon: Array = order.get("bonus", [])
	if not bon.is_empty():
		text += "\n[color=cyan]Bonus:[/color] "
		var bon_names: Array[String] = []
		for b in bon:
			bon_names.append(INGREDIENT_DISPLAY.get(b, b))
		text += ", ".join(bon_names)
	var price: int = order.get("price", 0)
	text += "\n[color=green]Pay: $%d[/color]" % price
	_order_label.text = text


func _update_money_display() -> void:
	if not _queue_manager:
		_money_label.text = "$0"
		_stats_label.text = ""
		return
	_money_label.text = "$%d" % _queue_manager._total_money
	_stats_label.text = "Served: %d | Lost: %d" % [_queue_manager._customers_served, _queue_manager._customers_angry]


func _on_money_changed(_total: int) -> void:
	_update_money_display()

func _on_customer_served(_count: int) -> void:
	_update_money_display()

func _on_customer_lost(_count: int) -> void:
	_update_money_display()


func _update_picked_display() -> void:
	if _selected_ingredients.is_empty():
		_picked_label.text = "[color=gray]Aim at food and click to pick...[/color]"
	else:
		var names: Array[String] = []
		for ing in _selected_ingredients:
			names.append(INGREDIENT_DISPLAY.get(ing, ing))
		_picked_label.text = "[b]Your Taco:[/b] " + ", ".join(names)


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
	prompt_panel.visible = false
	center_box.add_child(prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.text = "Press [E] to Cook Tacos"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 0.7))
	prompt_panel.add_child(_prompt_label)
	# Store panel ref so we can toggle visibility
	_prompt_label.set_meta("panel", prompt_panel)

	# Crosshair
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.visible = false
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	aim_panel.visible = false
	center_box.add_child(aim_panel)

	_aim_label = Label.new()
	_aim_label.text = ""
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_label.add_theme_font_size_override("font_size", 20)
	_aim_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	aim_panel.add_child(_aim_label)
	_aim_label.set_meta("panel", aim_panel)

	# ── Order panel (right side) ──
	_order_panel = PanelContainer.new()
	_order_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.05, 0.85)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	_order_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(_order_panel)
	_order_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_order_panel.offset_left = -260
	_order_panel.offset_top = 40
	_order_panel.offset_bottom = -40

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_order_panel.add_child(vbox)

	# Money
	_money_label = Label.new()
	_money_label.text = "$0"
	_money_label.add_theme_font_size_override("font_size", 22)
	_money_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	vbox.add_child(_money_label)

	# Stats
	_stats_label = Label.new()
	_stats_label.text = "Served: 0 | Lost: 0"
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_stats_label)

	# Order
	_order_label = RichTextLabel.new()
	_order_label.bbcode_enabled = true
	_order_label.fit_content = true
	_order_label.custom_minimum_size = Vector2(230, 60)
	vbox.add_child(_order_label)

	# Divider
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Picked
	_picked_label = RichTextLabel.new()
	_picked_label.bbcode_enabled = true
	_picked_label.fit_content = true
	_picked_label.custom_minimum_size = Vector2(230, 40)
	vbox.add_child(_picked_label)

	# Result
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_result_label)

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
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint_panel.add_child(_hint_label)
	_hint_label.set_meta("panel", hint_panel)
