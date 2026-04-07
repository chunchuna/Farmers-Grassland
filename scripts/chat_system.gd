extends CanvasLayer

## In-game chat system with multiplayer sync.
## Press Enter to open chat, type message, Enter to send, Escape to cancel.
## Also shows system messages for player join/leave.

var _chat_container: VBoxContainer
var _message_list: RichTextLabel
var _input_field: LineEdit
var _is_chatting := false

## Max messages shown
const MAX_MESSAGES := 50
## How long normal messages stay visible (seconds) when chat is not focused
const FADE_TIME := 8.0

var _fade_timer := 0.0
var _has_unread := false


func _ready() -> void:
	layer = 90
	_build_ui()
	_input_field.visible = false
	_message_list.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not _is_chatting:
				_open_chat()
				get_viewport().set_input_as_handled()
			else:
				_send_message()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _is_chatting:
			_close_chat()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _is_chatting:
		_message_list.modulate.a = 1.0
		_fade_timer = FADE_TIME
		return

	if _fade_timer > 0.0:
		_fade_timer -= delta
		if _fade_timer > 1.0:
			_message_list.modulate.a = 1.0
		else:
			_message_list.modulate.a = maxf(_fade_timer, 0.0)
	else:
		_message_list.modulate.a = 0.0


func _open_chat() -> void:
	_is_chatting = true
	_input_field.visible = true
	_input_field.grab_focus()
	_input_field.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_message_list.modulate.a = 1.0


func _close_chat() -> void:
	_is_chatting = false
	_input_field.visible = false
	_input_field.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_fade_timer = FADE_TIME


func _send_message() -> void:
	var text := _input_field.text.strip_edges()
	_close_chat()
	if text.is_empty():
		return

	var peer_id := 0
	if multiplayer.has_multiplayer_peer():
		peer_id = multiplayer.get_unique_id()

	var display_name := "Player %d" % peer_id if peer_id > 0 else "Player"
	var msg := "[color=#8cb4ff]%s[/color]: %s" % [display_name, _escape_bbcode(text)]
	_add_message(msg)

	if multiplayer.has_multiplayer_peer():
		_rpc_chat_message.rpc(msg)


## Add a system message (player join/leave, etc.)
func add_system_message(text: String) -> void:
	var msg := "[color=#888888][i]%s[/i][/color]" % text
	_add_message(msg)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_chat_message.rpc(msg)


## Send a system message only to a specific peer
func send_system_message_to(peer_id: int, text: String) -> void:
	var msg := "[color=#888888][i]%s[/i][/color]" % text
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_chat_message.rpc_id(peer_id, msg)


func _add_message(bbcode_msg: String) -> void:
	_message_list.append_text(bbcode_msg + "\n")
	_fade_timer = FADE_TIME
	_message_list.modulate.a = 1.0

	# Trim old messages
	var line_count := _message_list.get_line_count()
	if line_count > MAX_MESSAGES:
		_message_list.clear()


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat_message(msg: String) -> void:
	_add_message(msg)


func _build_ui() -> void:
	_chat_container = VBoxContainer.new()
	_chat_container.name = "ChatContainer"
	_chat_container.anchor_left = 0.0
	_chat_container.anchor_right = 0.4
	_chat_container.anchor_top = 0.65
	_chat_container.anchor_bottom = 1.0
	_chat_container.offset_left = 12.0
	_chat_container.offset_right = 0.0
	_chat_container.offset_top = 0.0
	_chat_container.offset_bottom = -12.0
	_chat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chat_container)

	# Message list
	_message_list = RichTextLabel.new()
	_message_list.name = "MessageList"
	_message_list.bbcode_enabled = true
	_message_list.scroll_following = true
	_message_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_list.add_theme_font_size_override("normal_font_size", 14)

	# Semi-transparent background
	var msg_style := StyleBoxFlat.new()
	msg_style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	msg_style.corner_radius_top_left = 6
	msg_style.corner_radius_top_right = 6
	msg_style.corner_radius_bottom_left = 6
	msg_style.corner_radius_bottom_right = 6
	msg_style.content_margin_left = 8
	msg_style.content_margin_right = 8
	msg_style.content_margin_top = 6
	msg_style.content_margin_bottom = 6
	_message_list.add_theme_stylebox_override("normal", msg_style)
	_chat_container.add_child(_message_list)

	# Input field
	_input_field = LineEdit.new()
	_input_field.name = "ChatInput"
	_input_field.placeholder_text = "Enter message..."
	_input_field.custom_minimum_size.y = 32
	_input_field.add_theme_font_size_override("font_size", 14)

	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	input_style.corner_radius_top_left = 4
	input_style.corner_radius_top_right = 4
	input_style.corner_radius_bottom_left = 4
	input_style.corner_radius_bottom_right = 4
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	input_style.border_width_top = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.3, 0.4, 0.6, 0.6)
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 4
	input_style.content_margin_bottom = 4
	_input_field.add_theme_stylebox_override("normal", input_style)
	_input_field.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_input_field.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5, 0.7))
	_chat_container.add_child(_input_field)

	_input_field.text_submitted.connect(_on_text_submitted)


func _on_text_submitted(_text: String) -> void:
	_send_message()
