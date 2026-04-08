extends Node3D

## A single NPC customer for the taco stand.
## Walks from spawn to queue position, shows order bubble, waits, then leaves.

enum State { WALKING_TO_QUEUE, WAITING, SERVED, LEAVING }

var state: State = State.WALKING_TO_QUEUE
var target_pos: Vector3 = Vector3.ZERO
var leave_pos: Vector3 = Vector3.ZERO
var walk_speed: float = 2.0
var order: Dictionary = {}
var patience: float = 60.0
var _patience_timer: float = 0.0
var _order_bubble: Label3D = null
var _money_label: Label3D = null
var queue_index: int = 0
var _angry_delay: float = 0.0

signal order_ready(customer: Node3D)
signal customer_left(customer: Node3D)
signal customer_angry(customer: Node3D)


func setup(order_data: Dictionary, queue_pos: Vector3, leave_position: Vector3, patience_time: float) -> void:
	order = order_data
	target_pos = queue_pos
	leave_pos = leave_position
	patience = patience_time
	_patience_timer = patience


func _ready() -> void:
	# Create order bubble (Label3D above head)
	_order_bubble = Label3D.new()
	_order_bubble.text = ""
	_order_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_order_bubble.no_depth_test = true
	_order_bubble.modulate = Color(1, 1, 1, 0.95)
	_order_bubble.font_size = 48
	_order_bubble.outline_size = 8
	_order_bubble.position = Vector3(0, 2.2, 0)
	_order_bubble.visible = false
	add_child(_order_bubble)

	# Money label (shows when served)
	_money_label = Label3D.new()
	_money_label.text = ""
	_money_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_money_label.no_depth_test = true
	_money_label.modulate = Color(0.2, 1.0, 0.3, 1.0)
	_money_label.font_size = 56
	_money_label.outline_size = 8
	_money_label.position = Vector3(0, 2.6, 0)
	_money_label.visible = false
	add_child(_money_label)


func _process(delta: float) -> void:
	match state:
		State.WALKING_TO_QUEUE:
			_walk_toward(target_pos, delta)
			if _xz_dist(global_position, target_pos) < 0.3:
				state = State.WAITING
				_show_order_bubble()
				order_ready.emit(self)

		State.WAITING:
			_face_direction(Vector3(3.5, global_position.y, -16.0))
			_patience_timer -= delta
			var ratio := _patience_timer / patience
			if ratio < 0.3:
				_order_bubble.modulate = Color(1.0, 0.3, 0.2, 0.95)
			elif ratio < 0.6:
				_order_bubble.modulate = Color(1.0, 0.8, 0.2, 0.95)
			if _patience_timer <= 0.0:
				_order_bubble.text = "!!!"
				_order_bubble.modulate = Color(1, 0, 0, 1)
				# Switch to SERVED temporarily to show angry text, then leave
				state = State.SERVED
				_angry_delay = 1.0
				customer_angry.emit(self)

		State.SERVED:
			# Brief delay before leaving (for money or angry display)
			_angry_delay -= delta
			if _angry_delay <= 0.0:
				_order_bubble.visible = false
				_money_label.visible = false
				state = State.LEAVING

		State.LEAVING:
			_walk_toward(leave_pos, delta)
			if _xz_dist(global_position, leave_pos) < 0.5:
				customer_left.emit(self)
				queue_free()


func serve(points: int, money: int) -> void:
	if state != State.WAITING:
		return
	state = State.SERVED
	_order_bubble.visible = false
	_money_label.text = "+$%d" % money
	_money_label.visible = true
	_angry_delay = 1.5


func serve_wrong() -> void:
	if state != State.WAITING:
		return
	_order_bubble.text = "Wrong!"
	_order_bubble.modulate = Color(1, 0.3, 0.1)
	# Will auto-restore after a brief pause via a timer
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(self) and state == State.WAITING:
			_show_order_bubble()
	)


func move_to_queue_pos(new_pos: Vector3) -> void:
	target_pos = new_pos
	if state == State.WAITING:
		state = State.WALKING_TO_QUEUE


func _walk_toward(target: Vector3, delta: float) -> void:
	var dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if dir.length() < 0.1:
		return
	var move := dir.normalized() * walk_speed * delta
	if move.length() > dir.length():
		global_position.x = target.x
		global_position.z = target.z
	else:
		global_position += move
	_face_direction(target)


func _face_direction(target: Vector3) -> void:
	var dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if dir.length() > 0.01:
		var angle := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, angle, 0.1)


func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _show_order_bubble() -> void:
	if order.is_empty():
		return
	# Show short ingredient list
	var req: Array = order.get("required", [])
	var display_map := {
		"tortilla": "Tort", "meat_asada": "Asada", "meat_pastor": "Pastor",
		"meat_shepherd": "Shep", "onion_cilantro": "Onion", "salsa_verde": "S.Verde",
		"salsa_roja": "S.Roja", "limon": "Lime", "salt": "Salt", "pepper": "Pepper",
	}
	var parts: Array[String] = []
	for r in req:
		parts.append(display_map.get(r, r))
	_order_bubble.text = order.get("name", "Taco") + "\n" + " + ".join(parts)
	_order_bubble.modulate = Color(1, 1, 1, 0.95)
	_order_bubble.visible = true
