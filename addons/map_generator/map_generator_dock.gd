@tool
extends VBoxContainer

## Editor dock that generates new multiplayer map scenes with all standard
## systems: WorldEnvironment, DirectionalLight3D, FillLight, GameManager,
## SpawnPoint, WeatherSystem, DebugPanel, ChatSystem.

# Known script/resource UIDs used in generated scenes
const ENV_DAY_PATH := "res://resources/env_day.tres"
const ENV_NIGHT_PATH := "res://resources/env_night.tres"
const GAME_MANAGER_SCRIPT := "res://scripts/game_manager.gd"
const WEATHER_SYSTEM_SCRIPT := "res://scripts/weather_system.gd"
const DEBUG_PANEL_SCRIPT := "res://scripts/debug_panel.gd"
const CHAT_SYSTEM_SCRIPT := "res://scripts/chat_system.gd"
const LOBBY_SCRIPT_PATH := "res://scripts/lobby_ui.gd"

# UIDs (for ext_resource references)
const UID_ENV_DAY := "uid://cfg6vrqq7ksno"
const UID_GM := "uid://d1m7g5qnsqxhi"
const UID_WEATHER := "uid://bhw2kv3shqrch"
const UID_DEBUG := "uid://dhetcbdynsu7f"
const UID_CHAT := "uid://c8thgl1c4sdsd"


func _ready() -> void:
	$AssetRow/BrowseBtn.pressed.connect(_on_browse_asset)
	$ColliderRow/ColliderBrowseBtn.pressed.connect(_on_browse_collider)
	$GenerateBtn.pressed.connect(_on_generate)
	$RemoveBtn.pressed.connect(_on_remove_map)

	# Populate environment selector
	$EnvSelect.add_item("Day (env_day.tres)")
	$EnvSelect.add_item("Night (env_night.tres)")
	$EnvSelect.selected = 0

	_refresh_map_list()


func _on_browse_asset() -> void:
	_open_file_dialog("Select 3D Asset", ["*.fbx", "*.gltf", "*.glb"], func(path: String):
		$AssetRow/AssetPath.text = path
	)


func _on_browse_collider() -> void:
	_open_file_dialog("Select Collider Asset", ["*.fbx", "*.gltf", "*.glb"], func(path: String):
		$ColliderRow/ColliderPath.text = path
	)


func _open_file_dialog(title: String, filters: PackedStringArray, callback: Callable) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = title
	for f in filters:
		dialog.add_filter(f)
	dialog.file_selected.connect(func(path: String):
		callback.call(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_generate() -> void:
	var map_name: String = $MapName.text.strip_edges().to_lower()
	if map_name.is_empty():
		_set_status("[color=red]Please enter a map name.[/color]")
		return

	# Sanitize name
	var safe_name := map_name.replace(" ", "_").replace("-", "_")
	var scene_path := "res://scenes/%s_map.tscn" % safe_name
	var root_name := safe_name.to_pascal_case() + "Map"

	var asset_path: String = $AssetRow/AssetPath.text.strip_edges()
	var collider_path: String = $ColliderRow/ColliderPath.text.strip_edges()
	var add_floor: bool = $FloorCheck.button_pressed
	var asset_scale: float = $ScaleRow/ScaleSpinBox.value
	var spawn_y: float = $SpawnRow/SpawnY.value
	var env_idx: int = $EnvSelect.selected
	var auto_register: bool = $RegisterCheck.button_pressed

	var env_path := ENV_DAY_PATH if env_idx == 0 else ENV_NIGHT_PATH
	var env_uid := UID_ENV_DAY if env_idx == 0 else ""

	_set_status("Generating scene...")

	# Build .tscn content
	var content := _build_scene_content(
		root_name, env_path, env_uid,
		asset_path, collider_path,
		add_floor, asset_scale, spawn_y
	)

	# Write scene file
	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	if not file:
		_set_status("[color=red]Failed to create file: %s[/color]" % scene_path)
		return
	file.store_string(content)
	file.close()

	var result_msg := "[color=green]Map scene created![/color]\n"
	result_msg += "• [b]%s[/b]\n" % scene_path

	# Auto-register in lobby
	if auto_register:
		var reg_ok := _register_in_lobby(safe_name, scene_path, map_name.capitalize())
		if reg_ok:
			result_msg += "• Registered in lobby_ui.gd\n"
		else:
			result_msg += "• [color=yellow]Could not auto-register in lobby[/color]\n"

	result_msg += "\n[color=gray]Open the scene in Godot to adjust SpawnPoint position and asset placement.[/color]"
	_set_status(result_msg)

	# Refresh editor filesystem
	EditorInterface.get_resource_filesystem().scan()
	_refresh_map_list()


func _build_scene_content(
	root_name: String, env_path: String, env_uid: String,
	asset_path: String, collider_path: String,
	add_floor: bool, asset_scale: float, spawn_y: float
) -> String:
	var ext_id := 1
	var ext_resources := ""
	var sub_resources := ""
	var nodes := ""

	# --- Ext Resources ---
	# Environment
	var env_id := "env_%d" % ext_id
	if env_uid.is_empty():
		ext_resources += '[ext_resource type="Environment" path="%s" id="%s"]\n' % [env_path, env_id]
	else:
		ext_resources += '[ext_resource type="Environment" uid="%s" path="%s" id="%s"]\n' % [env_uid, env_path, env_id]
	ext_id += 1

	# GameManager script
	var gm_id := "gm_%d" % ext_id
	ext_resources += '[ext_resource type="Script" uid="%s" path="%s" id="%s"]\n' % [UID_GM, GAME_MANAGER_SCRIPT, gm_id]
	ext_id += 1

	# WeatherSystem script
	var ws_id := "ws_%d" % ext_id
	ext_resources += '[ext_resource type="Script" uid="%s" path="%s" id="%s"]\n' % [UID_WEATHER, WEATHER_SYSTEM_SCRIPT, ws_id]
	ext_id += 1

	# DebugPanel script
	var dp_id := "dp_%d" % ext_id
	ext_resources += '[ext_resource type="Script" uid="%s" path="%s" id="%s"]\n' % [UID_DEBUG, DEBUG_PANEL_SCRIPT, dp_id]
	ext_id += 1

	# ChatSystem script
	var cs_id := "cs_%d" % ext_id
	ext_resources += '[ext_resource type="Script" uid="%s" path="%s" id="%s"]\n' % [UID_CHAT, CHAT_SYSTEM_SCRIPT, cs_id]
	ext_id += 1

	# 3D Asset
	var asset_id := ""
	if not asset_path.is_empty():
		asset_id = "asset_%d" % ext_id
		ext_resources += '[ext_resource type="PackedScene" path="%s" id="%s"]\n' % [asset_path, asset_id]
		ext_id += 1

	# Collider Asset
	var collider_id := ""
	if not collider_path.is_empty():
		collider_id = "collider_%d" % ext_id
		ext_resources += '[ext_resource type="PackedScene" path="%s" id="%s"]\n' % [collider_path, collider_id]
		ext_id += 1

	# --- Sub Resources ---
	if add_floor:
		sub_resources += '[sub_resource type="BoxShape3D" id="floor_box"]\n'
		sub_resources += 'size = Vector3(200, 1, 200)\n\n'

	# --- Nodes ---
	# Root
	nodes += '[node name="%s" type="Node3D"]\n\n' % root_name

	# WorldEnvironment
	nodes += '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\n'
	nodes += 'environment = ExtResource("%s")\n\n' % env_id

	# DirectionalLight3D (sun)
	nodes += '[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]\n'
	nodes += 'transform = Transform3D(-0.5943767, 0.77947974, -0.19780819, -0.093115, 0.17760977, 0.97968245, 0.7987776, 0.6007279, -0.03297293, 0, 30, 0)\n'
	nodes += 'light_color = Color(1, 0.95, 0.85, 1)\n'
	nodes += 'light_energy = 0.7\n'
	nodes += 'light_angular_distance = 1.0\n'
	nodes += 'shadow_enabled = true\n'
	nodes += 'shadow_bias = 0.03\n\n'

	# FillLight
	nodes += '[node name="FillLight" type="DirectionalLight3D" parent="."]\n'
	nodes += 'transform = Transform3D(0.866, 0.354, -0.354, 0, 0.707, 0.707, 0.5, -0.612, 0.612, 0, 20, 0)\n'
	nodes += 'light_color = Color(0.6, 0.7, 0.9, 1)\n'
	nodes += 'light_energy = 0.3\n\n'

	# 3D Asset
	if not asset_id.is_empty():
		var asset_node_name := asset_path.get_file().get_basename()
		nodes += '[node name="%s" parent="." instance=ExtResource("%s")]\n' % [asset_node_name, asset_id]
		if asset_scale != 1.0:
			nodes += 'transform = Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, 0)\n' % [asset_scale, asset_scale, asset_scale]
		nodes += '\n'

	# Collider Asset
	if not collider_id.is_empty():
		var col_node_name := collider_path.get_file().get_basename()
		nodes += '[node name="%s" parent="." instance=ExtResource("%s")]\n' % [col_node_name, collider_id]
		if asset_scale != 1.0:
			nodes += 'transform = Transform3D(%s, 0, 0, 0, %s, 0, 0, 0, %s, 0, 0, 0)\n' % [asset_scale, asset_scale, asset_scale]
		nodes += '\n'

	# Floor collision
	if add_floor:
		nodes += '[node name="FloorCollision" type="StaticBody3D" parent="."]\n\n'
		nodes += '[node name="CollisionShape3D" type="CollisionShape3D" parent="FloorCollision"]\n'
		nodes += 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)\n'
		nodes += 'shape = SubResource("floor_box")\n\n'

	# SpawnPoint
	nodes += '[node name="SpawnPoint" type="Marker3D" parent="."]\n'
	nodes += 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\n' % spawn_y
	nodes += 'gizmo_extents = 1.5\n\n'

	# GameManager + SpawnContainer
	nodes += '[node name="GameManager" type="Node" parent="."]\n'
	nodes += 'script = ExtResource("%s")\n\n' % gm_id
	nodes += '[node name="SpawnContainer" type="Node" parent="GameManager"]\n\n'

	# WeatherSystem
	nodes += '[node name="WeatherSystem" type="Node3D" parent="."]\n'
	nodes += 'script = ExtResource("%s")\n\n' % ws_id

	# DebugPanel
	nodes += '[node name="DebugPanel" type="CanvasLayer" parent="."]\n'
	nodes += 'script = ExtResource("%s")\n\n' % dp_id

	# ChatSystem
	nodes += '[node name="ChatSystem" type="CanvasLayer" parent="."]\n'
	nodes += 'script = ExtResource("%s")\n' % cs_id

	# Assemble
	var result := "[gd_scene format=3]\n\n"
	result += ext_resources + "\n"
	if not sub_resources.is_empty():
		result += sub_resources
	result += nodes
	return result


func _register_in_lobby(safe_name: String, scene_path: String, display_name: String) -> bool:
	if not FileAccess.file_exists(LOBBY_SCRIPT_PATH):
		return false

	var file := FileAccess.open(LOBBY_SCRIPT_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	# Check if already registered
	if scene_path in content:
		return true  # Already there

	# Find the closing bracket of MAPS array and insert before it
	var insert_target := "]\nconst DEFAULT_PORT"
	var new_entry := '\t{"name": "%s", "scene": "%s"},\n' % [display_name, scene_path]
	var new_content := content.replace(insert_target, new_entry + insert_target)

	if new_content == content:
		# Fallback: try different pattern
		return false

	var out_file := FileAccess.open(LOBBY_SCRIPT_PATH, FileAccess.WRITE)
	out_file.store_string(new_content)
	out_file.close()
	return true


func _refresh_map_list() -> void:
	$MapList.clear()
	var maps := _parse_lobby_maps()
	for m in maps:
		$MapList.add_item("%s  →  %s" % [m["name"], m["scene"]])


func _parse_lobby_maps() -> Array:
	var maps: Array = []
	if not FileAccess.file_exists(LOBBY_SCRIPT_PATH):
		return maps
	var file := FileAccess.open(LOBBY_SCRIPT_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	# Extract each {"name": "...", "scene": "..."} line
	var regex := RegEx.new()
	regex.compile('\\{"name":\\s*"([^"]+)",\\s*"scene":\\s*"([^"]+)"\\}')
	var results := regex.search_all(content)
	for result in results:
		maps.append({"name": result.get_string(1), "scene": result.get_string(2)})
	return maps


func _on_remove_map() -> void:
	var selected: PackedInt32Array = $MapList.get_selected_items()
	if selected.is_empty():
		_set_status("[color=yellow]Select a map from the list first.[/color]")
		return

	var idx: int = selected[0]
	var maps := _parse_lobby_maps()
	if idx < 0 or idx >= maps.size():
		return

	var map_to_remove: Dictionary = maps[idx]
	var removed := _unregister_from_lobby(map_to_remove["scene"])
	if removed:
		_set_status("[color=green]Removed [b]%s[/b] from lobby map list.[/color]" % map_to_remove["name"])
		_refresh_map_list()
	else:
		_set_status("[color=red]Failed to remove map from lobby_ui.gd[/color]")


func _unregister_from_lobby(scene_path: String) -> bool:
	if not FileAccess.file_exists(LOBBY_SCRIPT_PATH):
		return false

	var file := FileAccess.open(LOBBY_SCRIPT_PATH, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	# Remove the line containing this scene path
	var lines := content.split("\n")
	var new_lines: PackedStringArray = []
	var found := false
	for line in lines:
		if scene_path in line and '"scene"' in line:
			found = true
			continue  # Skip this line
		new_lines.append(line)

	if not found:
		return false

	var out_file := FileAccess.open(LOBBY_SCRIPT_PATH, FileAccess.WRITE)
	out_file.store_string("\n".join(new_lines))
	out_file.close()
	return true


func _set_status(text: String) -> void:
	$StatusLabel.text = text
