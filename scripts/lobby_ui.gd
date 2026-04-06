extends Control

const GAME_SCENE := "res://scenes/grassland.tscn"
const DEFAULT_PORT := 7000

@onready var ip_input: LineEdit = $Panel/VBoxContainer/IPInput
@onready var port_input: LineEdit = $Panel/VBoxContainer/PortInput
@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ip_input.text = "127.0.0.1"
	port_input.text = str(DEFAULT_PORT)
	status_label.text = ""


func _on_host_pressed() -> void:
	var port := int(port_input.text) if port_input.text.is_valid_int() else DEFAULT_PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		status_label.text = "Failed to host: %s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Hosting on port %d... Loading game..." % port
	print("Server created on port %d" % port)
	# Small delay so user can see the message
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join_pressed() -> void:
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := int(port_input.text) if port_input.text.is_valid_int() else DEFAULT_PORT

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_label.text = "Failed to connect: %s" % error_string(err)
		return

	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s:%d..." % [address, port]

	# Wait for connection result
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)


func _on_connected() -> void:
	print("Connected! My ID: %d" % multiplayer.get_unique_id())
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_failed() -> void:
	status_label.text = "Connection failed! Is the host running?"
	multiplayer.multiplayer_peer = null
