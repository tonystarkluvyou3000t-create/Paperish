extends RefCounted
## Frozen read model: primitives and value types only, no mutable service handles.
var _values: Dictionary

func _init(values: Dictionary) -> void:
	_values = values.duplicate(true)
	_values.make_read_only()

func to_dictionary() -> Dictionary:
	# An isolated copy for compatibility with JSON; never the owner's state.
	return _values.duplicate(true)

func is_read_only() -> bool:
	return _values.is_read_only()

var mode: String:
	get: return _values.get("mode", "title")
var session_mode: String:
	get: return _values.get("session_mode", "title")
var actor_mode: String:
	get: return _values.get("actor_mode", "foot")
var order_lifecycle: String:
	get: return _values.get("order_lifecycle", "idle")
var generation: int:
	get: return _values.get("generation", 0)
var order_id: int:
	get: return _values.get("order_id", 0)
var order_count: int:
	get: return _values.get("order_count", 0)
var cargo_inventory: String:
	get: return _values.get("cargo_inventory", "NO BOXES IN TRANSIT")
var van_cargo_count: int:
	get: return _values.get("van_cargo_count", 0)
var van_capacity: int:
	get: return _values.get("van_capacity", 0)
var ticket_state: String:
	get: return _values.get("ticket_state", "none")
var preparation_remaining: float:
	get: return _values.get("preparation_remaining", 0.0)
var ticket_customer: String:
	get: return _values.get("ticket_customer", "")
var destination_id: String:
	get: return _values.get("destination_id", "")
var cargo_count: int:
	get: return _values.get("cargo_count", 0)
var order_pizzas: int:
	get: return _values.get("order_pizzas", 1)
var money: int:
	get: return _values.get("money", 0)
var goal_money: int:
	get: return _values.get("goal_money", 150)
var deliveries: int:
	get: return _values.get("deliveries", 0)
var strikes: int:
	get: return _values.get("strikes", 0)
var tip: int:
	get: return _values.get("tip", 0)
var timer: float:
	get: return _values.get("timer", 0.0)
var timer_max: float:
	get: return _values.get("timer_max", 60.0)
var speed: float:
	get: return _values.get("speed", 0.0)
var speed_kmh: float:
	get: return _values.get("speed_kmh", 0.0)
var driving: bool:
	get: return _values.get("driving", false)
var paused: bool:
	get: return _values.get("paused", false)
var world_ready: bool:
	get: return _values.get("world_ready", false)
var timer_visible: bool:
	get: return _values.get("timer_visible", false)
var pip_control: bool:
	get: return _values.get("pip_control", false)
var van_control: bool:
	get: return _values.get("van_control", false)
var van_stopped: bool:
	get: return _values.get("van_stopped", true)
var pip_autopilot: bool:
	get: return _values.get("pip_autopilot", false)
var van_autopilot: bool:
	get: return _values.get("van_autopilot", false)
var pip_visible: bool:
	get: return _values.get("pip_visible", true)
var pip_collision: bool:
	get: return _values.get("pip_collision", true)
var pickup_distance: float:
	get: return _values.get("pickup_distance", -1.0)
var door_distance: float:
	get: return _values.get("door_distance", -1.0)
var park_distance: float:
	get: return _values.get("park_distance", -1.0)
var pip_x: float:
	get: return _values.get("pip_x", 0.0)
var pip_z: float:
	get: return _values.get("pip_z", 0.0)
var van_x: float:
	get: return _values.get("van_x", 0.0)
var van_z: float:
	get: return _values.get("van_z", 0.0)
var pip_motion: float:
	get: return _values.get("pip_motion", 0.0)
var van_motion: float:
	get: return _values.get("van_motion", 0.0)
var objective_text: String:
	get: return _values.get("objective_text", "")
var target_label: String:
	get: return _values.get("target_label", "")
var target_sub: String:
	get: return _values.get("target_sub", "")
var prompt_text: String:
	get: return _values.get("prompt_text", "")
var waypoint_visible: bool:
	get: return _values.get("waypoint_visible", false)
var waypoint_position: Vector3:
	get: return _values.get("waypoint_position", Vector3.ZERO)
var waypoint_color: Color:
	get: return _values.get("waypoint_color", Color.WHITE)
var camera_mode: String:
	get: return _values.get("camera_mode", "title")
var camera_hint: String:
	get: return _values.get("camera_hint", "")
var play_mode: String:
	get: return _values.get("play_mode", "shift")
var gameplay_visible: bool:
	get: return _values.get("gameplay_visible", false)
var menu_screen: String:
	get: return _values.get("menu_screen", "")
var menu_focused: String:
	get: return _values.get("menu_focused", "")
var total_base: int:
	get: return _values.get("total_base", 0)
var total_pizza: int:
	get: return _values.get("total_pizza", 0)
var total_tip: int:
	get: return _values.get("total_tip", 0)
var actor_position: Vector3:
	get: return _values.get("actor_position", Vector3.ZERO)
