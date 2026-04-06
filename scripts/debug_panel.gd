extends CanvasLayer

## Debug panel toggled by HOME key.
## Provides weather controls and other debug options.

var _panel: PanelContainer
var _weather_system: Node
var _visible := false


func _ready() -> void:
	layer = 100
	_build_ui()
	_panel.visible = false

	# Find weather system (wait a frame so scene is fully loaded)
	await get_tree().process_frame
	_weather_system = get_tree().root.get_node_or_null("Grassland/WeatherSystem")
	if not _weather_system:
		# Fallback: search all children
		_weather_system = _find_node_by_name(get_tree().root, "WeatherSystem")
	if _weather_system:
		print("DebugPanel: Found WeatherSystem at %s" % _weather_system.get_path())
	else:
		push_warning("DebugPanel: WeatherSystem not found!")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			_visible = not _visible
			_panel.visible = _visible
			if _visible:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DebugPanelContainer"

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.4, 0.6, 0.8)
	_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)
	margin.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Debug Panel  [HOME]"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Weather section header
	var weather_label := Label.new()
	weather_label.text = "Weather"
	weather_label.add_theme_font_size_override("font_size", 16)
	weather_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	vbox.add_child(weather_label)

	# Weather buttons
	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_container)

	var btn_clear := _create_button("☀ Clear", Color(0.9, 0.8, 0.3))
	btn_clear.pressed.connect(_on_weather_clear)
	btn_container.add_child(btn_clear)

	var btn_rain := _create_button("🌧 Rain", Color(0.4, 0.5, 0.8))
	btn_rain.pressed.connect(_on_weather_rain)
	btn_container.add_child(btn_rain)

	var btn_snow := _create_button("❄ Snow", Color(0.8, 0.85, 1.0))
	btn_snow.pressed.connect(_on_weather_snow)
	btn_container.add_child(btn_snow)

	# Info label
	vbox.add_child(HSeparator.new())
	var info := Label.new()
	info.text = "Press HOME to close"
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(info)


func _create_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 36)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.18, 0.25, 0.9)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = color * 0.6
	style_normal.content_margin_left = 10
	style_normal.content_margin_right = 10
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = Color(0.2, 0.25, 0.35, 0.95)
	style_hover.border_color = color
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = color * 0.3
	style_pressed.border_color = color
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_color_override("font_color", color)
	btn.add_theme_font_size_override("font_size", 14)
	return btn


func _on_weather_clear() -> void:
	if _weather_system and _weather_system.has_method("set_weather"):
		print("DebugPanel: Setting weather to CLEAR")
		_weather_system.set_weather(0)  # WeatherType.CLEAR
	else:
		push_warning("DebugPanel: WeatherSystem not available")


func _on_weather_rain() -> void:
	if _weather_system and _weather_system.has_method("set_weather"):
		print("DebugPanel: Setting weather to RAIN")
		_weather_system.set_weather(1)  # WeatherType.RAIN
	else:
		push_warning("DebugPanel: WeatherSystem not available")


func _on_weather_snow() -> void:
	if _weather_system and _weather_system.has_method("set_weather"):
		print("DebugPanel: Setting weather to SNOW")
		_weather_system.set_weather(2)  # WeatherType.SNOW
	else:
		push_warning("DebugPanel: WeatherSystem not available")


func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, node_name)
		if found:
			return found
	return null
