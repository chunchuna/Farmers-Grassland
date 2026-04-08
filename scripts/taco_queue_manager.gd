extends Node3D

## Manages NPC customer queue for the taco stand.
## Spawns customers at intervals, assigns queue positions,
## connects their orders to the cooking system.

@export var max_queue_length: int = 5
@export var spawn_interval_min: float = 8.0
@export var spawn_interval_max: float = 15.0
@export var customer_patience: float = 60.0
@export var queue_spacing: float = 1.4
@export var customer_scale: float = 0.5
@export var bubble_font_size: int = 28
@export var bubble_ingredient_font_size: int = 22

# Queue origin: read from GuKePoint Marker3D at runtime
var _queue_origin: Vector3 = Vector3.ZERO
var queue_direction: Vector3 = Vector3(1.0, 0.0, 0.0)  # Customers line up along +X
var spawn_offset: Vector3 = Vector3(20.0, 0.0, 10.0)  # Where customers spawn from (relative to queue origin)
var leave_offset: Vector3 = Vector3(-20.0, 0.0, 10.0)  # Where they walk away to

# Character model paths (civilians only)
const MALE_MODELS: Array[String] = [
	"res://Assest/people/Characters_psx/Models/Male/Character_01.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_02.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_03.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_04.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_05.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_06.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_07.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_08.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_09.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_10.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_11.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_12.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_13.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_14.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_15.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_16.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_29.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_30.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_31.fbx",
	"res://Assest/people/Characters_psx/Models/Male/Character_32.fbx",
]

const FEMALE_MODELS: Array[String] = [
	"res://Assest/people/Characters_psx/Models/Female/Character_27_Female_HM.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_28_Female_HM.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_29_Female.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_30_Female.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_31_Female.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_32_Female.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_33_Female.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_Female_01.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_Female_02.fbx",
	"res://Assest/people/Characters_psx/Models/Female/Character_Female_03.fbx",
]

const RECIPES := [
	{
		"name": "Classic Asada",
		"required": ["tortilla", "meat_asada", "onion_cilantro"],
		"bonus": ["salsa_verde", "limon"],
		"base_score": 100,
		"price": 35,
	},
	{
		"name": "Al Pastor",
		"required": ["tortilla", "meat_pastor", "salsa_roja"],
		"bonus": ["onion_cilantro", "limon"],
		"base_score": 120,
		"price": 40,
	},
	{
		"name": "Shepherd Special",
		"required": ["tortilla", "meat_shepherd", "onion_cilantro", "salsa_verde"],
		"bonus": ["limon", "salt"],
		"base_score": 150,
		"price": 50,
	},
	{
		"name": "Double Meat",
		"required": ["tortilla", "meat_asada", "meat_pastor", "salsa_roja"],
		"bonus": ["onion_cilantro", "pepper"],
		"base_score": 180,
		"price": 60,
	},
	{
		"name": "Lime Taco",
		"required": ["tortilla", "meat_asada", "limon", "salt"],
		"bonus": ["pepper"],
		"base_score": 90,
		"price": 25,
	},
]

var _queue: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _next_spawn_time: float = 3.0  # First customer comes quickly
var _total_money: int = 0
var _customers_served: int = 0
var _customers_angry: int = 0
var _active: bool = false
var _loaded_scenes: Dictionary = {}  # path -> PackedScene cache

# Preloaded customer script
var _customer_script: GDScript

signal money_changed(total: int)
signal customer_served(count: int)
signal customer_lost(count: int)


func _ready() -> void:
	_customer_script = load("res://scripts/taco_customer.gd") as GDScript
	# Find GuKePoint marker for queue start position
	var marker := get_node_or_null("/root/TacoMap/GuKePoint")
	if not marker:
		marker = get_node_or_null("../GuKePoint")
	if marker:
		_queue_origin = marker.global_position
	else:
		_queue_origin = global_position + Vector3(2.0, 0.0, -2.5)
		push_warning("TacoQueue: GuKePoint not found, using default position")


func start_queue() -> void:
	_active = true
	_spawn_timer = 0.0
	_next_spawn_time = 2.0
	_total_money = 0
	_customers_served = 0
	_customers_angry = 0


func stop_queue() -> void:
	_active = false
	# Remove all queued customers
	for c in _queue.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	_queue.clear()


func get_front_customer() -> Node3D:
	if _queue.is_empty():
		return null
	return _queue[0]


func get_front_order() -> Dictionary:
	var front := get_front_customer()
	if not front:
		return {}
	return front.order


func serve_front_customer(selected_ingredients: Array[String]) -> Dictionary:
	var front := get_front_customer()
	if not front or front.state != front.State.WAITING:
		return {"success": false, "message": "No customer waiting"}

	var order: Dictionary = front.order
	var required: Array = order.get("required", [])
	var bonus: Array = order.get("bonus", [])

	var required_met := 0
	for ing in required:
		if ing in selected_ingredients:
			required_met += 1

	if required_met == required.size():
		# Calculate score
		var points: int = order.get("base_score", 100)
		var price: int = order.get("price", 30)
		var bonus_count := 0
		for ing in bonus:
			if ing in selected_ingredients:
				bonus_count += 1
				points += 25
				price += 5

		# Tip based on patience remaining
		var patience_ratio: float = front._patience_timer / front.patience
		var tip := int(price * patience_ratio * 0.3)
		price += tip

		_total_money += price
		_customers_served += 1
		money_changed.emit(_total_money)
		customer_served.emit(_customers_served)

		front.serve(points, price)
		_queue.erase(front)
		_reposition_queue()

		return {
			"success": true,
			"points": points,
			"money": price,
			"tip": tip,
			"message": "Served! +$%d (tip: $%d)" % [price, tip],
		}
	else:
		front.serve_wrong()
		var missing := required.size() - required_met
		return {
			"success": false,
			"message": "Wrong! Missing %d ingredient(s)" % missing,
		}


func _process(delta: float) -> void:
	if not _active:
		return

	_spawn_timer += delta
	if _spawn_timer >= _next_spawn_time and _queue.size() < max_queue_length:
		_spawn_customer()
		_spawn_timer = 0.0
		_next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)


func _spawn_customer() -> void:
	# Pick random model
	var all_models: Array[String] = []
	all_models.append_array(MALE_MODELS)
	all_models.append_array(FEMALE_MODELS)
	var model_path: String = all_models[randi() % all_models.size()]

	# Load model scene (cached)
	var scene: PackedScene
	if model_path in _loaded_scenes:
		scene = _loaded_scenes[model_path]
	else:
		scene = load(model_path) as PackedScene
		if scene:
			_loaded_scenes[model_path] = scene
	if not scene:
		push_warning("TacoQueue: Could not load model: " + model_path)
		return

	# Create customer Node3D
	var customer := Node3D.new()
	customer.set_script(_customer_script)
	customer.name = "Customer_%d" % randi()

	# Add the character model as child
	var model_instance := scene.instantiate()
	model_instance.scale = Vector3.ONE * customer_scale
	customer.add_child(model_instance)

	# Calculate queue position
	var queue_idx := _queue.size()
	var queue_pos := _get_queue_position(queue_idx)
	var spawn_pos := _queue_origin + spawn_offset
	spawn_pos.y = 0.0

	# Pick random order
	var order_data: Dictionary = RECIPES[randi() % RECIPES.size()].duplicate(true)

	# Setup and spawn
	customer.global_position = spawn_pos
	customer.setup(order_data, queue_pos, _queue_origin + leave_offset, customer_patience)
	customer.bubble_name_font_size = bubble_font_size
	customer.bubble_ingredient_font_size = bubble_ingredient_font_size
	customer.walk_speed = randf_range(1.5, 2.5)
	customer.queue_index = queue_idx

	# Connect signals
	customer.customer_left.connect(_on_customer_left)
	customer.customer_angry.connect(_on_customer_angry)

	add_child(customer)
	_queue.append(customer)


func _get_queue_position(index: int) -> Vector3:
	var pos := _queue_origin + queue_direction * (index * queue_spacing)
	pos.y = 0.0
	return pos


func _reposition_queue() -> void:
	for i in _queue.size():
		var c: Node3D = _queue[i]
		if is_instance_valid(c):
			c.queue_index = i
			c.move_to_queue_pos(_get_queue_position(i))


func _on_customer_left(customer: Node3D) -> void:
	if customer in _queue:
		_queue.erase(customer)
		_reposition_queue()


func _on_customer_angry(customer: Node3D) -> void:
	_customers_angry += 1
	customer_lost.emit(_customers_angry)
	if customer in _queue:
		_queue.erase(customer)
		_reposition_queue()
