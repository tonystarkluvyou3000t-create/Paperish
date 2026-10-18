extends Node3D
## Pip the Pizza Boy - the shift.
## Take the order, grab the pizzas at the shop, drive to the address, park, hop
## out and deliver on foot before the clock runs out. Three timeouts end the day.

enum State { TITLE, TO_SHOP, TO_HOUSE, COMPLETE, FAILED }

const Snapshot = preload("res://scripts/services/game_snapshot.gd")
const Presentation = preload("res://scripts/services/presentation.gd")
const SoundPresenter = preload("res://scripts/services/sound_presenter.gd")
var presentation := Presentation.new()
var sound := SoundPresenter.new()
const OrderService = preload("res://scripts/services/order_service.gd")
const Balance = preload("res://scripts/services/balance.gd")
@export var balance: Balance = preload("res://data/balance.tres")
var orders := OrderService.new()
const SessionService = preload("res://scripts/services/session_service.gd")
const ActorController = preload("res://scripts/services/actor_controller.gd")
const WorldRegistry = preload("res://scripts/services/world_registry.gd")
var session := SessionService.new()
var actors := ActorController.new()
var world := WorldRegistry.new()
var _generation: int:
	get: return session.generation

const SessionInput = preload("res://scripts/session_input.gd")

var stopped_speed: float:
	get: return balance.stopped_speed

var state: State:
	get:
		if session.flow == session.Flow.TITLE: return State.TITLE
		if session.flow == session.Flow.RESULT: return State.COMPLETE if session.outcome == "won" else State.FAILED
		return State.TO_HOUSE if orders.lifecycle == orders.Lifecycle.ON_ROUTE else State.TO_SHOP
var money: int:
	get: return orders.money
var goal_money: int:
	get: return balance.goal_money
var deliveries: int:
	get: return orders.deliveries
var strikes: int:
	get: return orders.strikes
var max_strikes: int:
	get: return balance.max_strikes
var order_house: Node3D:
	get:
		return world.destination(orders.destination_id)
var order_pizzas: int:
	get: return orders.pizzas
var timer: float:
	get: return orders.remaining
var timer_max: float:
	get: return orders.duration
var timer_visible: bool:
	get: return is_shift_active()
var last_house: int:
	get:
		for i in range(houses.size()):
			if str(houses[i].get_meta("address")) == orders.last_destination: return i
		return -1
var paused: bool:
	get: return session.paused

# ---- values the HUD reads every frame
var objective_text: String:
	get: return presentation.objective_text
var target_label: String:
	get: return presentation.target_label
var target_sub: String:
	get: return presentation.target_sub
var prompt_text: String:
	get: return presentation.prompt_text
var waypoint_position: Vector3:
	get: return presentation.waypoint_position
var waypoint_visible: bool:
	get: return presentation.waypoint_visible
var waypoint_color: Color:
	get: return presentation.waypoint_color
var speed_kmh: float:
	get: return absf(van.speed) * 3.6 if driving else 0.0
var driving: bool:
	get: return actors.driving

@onready var town: Node3D = get_node_or_null("Town") as Node3D
@onready var pip: CharacterBody3D = get_node_or_null("Pip") as CharacterBody3D
@onready var van: CharacterBody3D = get_node_or_null("Van") as CharacterBody3D
@onready var camera: Camera3D = get_node_or_null("Camera") as Camera3D

var hud: CanvasLayer
var houses: Array[Node3D]:
	get: return world.houses
var pickup_point: Node3D:
	get: return world.pickup_point
var pickup_marker: Node3D:
	get: return presentation.pickup_marker
var deliver_marker: Node3D:
	get: return presentation.deliver_marker
var world_ready := false
var world_errors: Array[String]:
	get: return world.world_errors
var active_order_id: int:
	get: return orders.order_id


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	randomize()
	orders.name = "Orders"
	orders.config = balance
	add_child(orders)
	session.name = "Session"
	add_child(session)
	actors.name = "Actors"
	add_child(actors)
	orders.shift_ended.connect(_on_shift_ended)
	hud = $HUD
	presentation.name = "Presentation"
	add_child(presentation)
	sound.name = "Sound"
	add_child(sound)
	hud.snapshot_provider = get_snapshot

	var input_owner := SessionInput.new()
	input_owner.name = "SessionInput"
	input_owner.game = self
	add_child(input_owner)

	world_ready = world.bind(self)
	if not world_ready:
		if pip:
			pip.input_enabled = false
			pip.set_physics_process(false)
		if van:
			van.input_enabled = false
			van.set_physics_process(false)
		session.invalidate_world()
		hud.show_title(false)
		hud.set_summary("WORLD SETUP ERROR", "\n".join(world_errors))
		hud.show_summary(true)
		set_process(false)
		return

	pip.cargo_source = orders
	actors.configure(pip, van, camera, session, balance)
	sound.configure(van)
	presentation.configure(hud, world, orders, actors, session, balance, sound)
	orders.settled.connect(actors.on_settlement)
	pip.footstep.connect(sound.footstep)
	van.honked.connect(sound.honk)

	restart()


# ------------------------------------------------------------------ input
func is_shift_active() -> bool:
	return world_ready and session.flow == session.Flow.PLAYING


func _sync_movement() -> void:
	actors.sync()


func _cancel_motion() -> void:
	actors.cancel_motion()


func _toggle_pause() -> void:
	if is_shift_active(): session.toggle_pause()


func open_modal(reason: StringName) -> bool:
	return session.open_modal(reason)


func close_modal(reason: StringName) -> bool:
	return session.close_modal(reason)


func restart() -> void:
	if not world_ready: return
	orders.reset(session.generation + 1)
	actors.reset(world.player_spawn, world.van_spawn)
	session.reset()


func start_shift() -> bool:
	if not world_ready or state != State.TITLE: return false
	if not session.start(): return false
	_new_order()
	_sync_movement()
	return true


func _start_shift() -> void:
	start_shift()


# ------------------------------------------------------------------ shift flow
func destination_ids() -> Array[String]:
	return world.ids()


func force_destination_index(index: int) -> bool:
	return orders.force_destination(world.legacy_id(index), world.ids())


func _new_order() -> void:
	if not world_ready or paused or state in [State.COMPLETE, State.FAILED]: return
	orders.create_ticket(destination_ids())


func _pick_up() -> void:
	if is_shift_active() and not paused and not driving:
		orders.pickup()


func _deliver() -> void:
	if is_shift_active() and not paused and not driving:
		orders.settle(destination_ids(), _generation, orders.order_id)


func _on_timeout() -> void:
	if is_shift_active() and not paused:
		orders.expire(destination_ids(), _generation, orders.order_id)


func _on_shift_ended(event: Dictionary) -> void:
	_finish(event.outcome == "won")


func _finish(win: bool) -> void:
	if not is_shift_active() or paused: return
	orders.close()
	session.finish(win)


func _process(delta: float) -> void:
	if not world_ready or paused: return
	if is_shift_active():
		orders.tick(delta, destination_ids())
		if is_shift_active(): presentation.update_context()


func _current_tip() -> int:
	return orders.tip()


func _context() -> void:
	presentation.update_context()


func interact() -> void:
	if not is_shift_active() or paused:
		return
	if driving:
		_exit_van()
		return
	_try_pickup_or_deliver()


func _on_interact() -> void:
	interact()


func force_destination(id: String) -> bool:
	return orders.force_destination(id, world.ids())


func _try_pickup_or_deliver() -> void:
	if not is_shift_active() or paused or driving:
		return
	var p := pip.global_position
	var door_pos: Vector3 = (order_house.get_node("Door") as Node3D).global_position if order_house else Vector3.ZERO
	if state == State.TO_SHOP and p.distance_to(pickup_point.global_position) < balance.pickup_range:
		_pick_up()
		return
	if state == State.TO_HOUSE and p.distance_to(door_pos) < balance.door_range:
		_deliver()
		return
	if not driving and p.distance_to(van.global_position) < balance.van_range:
		_enter_van()


func _van_stopped() -> bool:
	return actors.stopped()


func _enter_van() -> bool:
	return actors.enter()


func _exit_van() -> bool:
	return actors.exit()


func set_order_seed(value: int) -> void:
	orders.set_seed(value)


func _diagnostic_values() -> Dictionary:
	if not world_ready: return {"mode": "failed", "world_ready": false}
	var mode: String = ["title", "to_shop", "to_house", "complete", "failed"][state]
	return {
		"mode": mode, "order_id": active_order_id,
		"destination_id": str(order_house.get_meta("address", "")) if order_house else "",
		"cargo_count": pip.carrying, "order_pizzas": order_pizzas,
		"deliveries": deliveries, "money": money, "strikes": strikes,
		"driving": driving, "paused": paused, "timer": timer, "timer_max": timer_max,
		"pip_control": pip.input_enabled, "van_control": van.input_enabled,
		"van_stopped": _van_stopped(), "speed": van.speed,
		"pip_autopilot": pip.autopilot != Vector3.INF, "van_autopilot": van.autopilot != Vector3.INF,
		"pickup_distance": pip.global_position.distance_to(pickup_point.global_position),
		"door_distance": pip.global_position.distance_to(order_house.get_node("Door").global_position) if order_house else -1.0,
		"park_distance": van.global_position.distance_to(order_house.get_node("Park").global_position) if order_house else -1.0,
		"pip_x": pip.global_position.x, "pip_z": pip.global_position.z,
		"van_x": van.global_position.x, "van_z": van.global_position.z,
		"pip_visible": pip.visible, "pip_collision": not pip.get_node("Collision").disabled,
		"pip_motion": pip.velocity.length(), "van_motion": van.velocity.length(),
		"tip": _current_tip(), "world_ready": world_ready,
	}


func get_snapshot() -> Snapshot:
	var values := _diagnostic_values()
	values.merge({
		"generation": session.generation,
		"session_mode": "paused" if session.paused else ["title", "playing", "result"][session.flow],
		"actor_mode": "driving" if driving else "foot",
		"order_lifecycle": ["idle", "at_shop", "on_route", "closed"][orders.lifecycle],
		"goal_money": goal_money, "timer_visible": timer_visible, "speed_kmh": speed_kmh,
		"objective_text": objective_text, "target_label": target_label, "target_sub": target_sub,
		"prompt_text": prompt_text, "waypoint_visible": waypoint_visible,
		"waypoint_position": waypoint_position, "waypoint_color": waypoint_color,
		"actor_position": (van.global_position if driving else pip.global_position) if world_ready else Vector3.ZERO,
	})
	return Snapshot.new(values)


func get_diagnostics() -> Dictionary:
	return get_snapshot().to_dictionary()
