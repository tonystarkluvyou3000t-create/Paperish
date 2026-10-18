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
const SettingsService = preload("res://scripts/services/settings_service.gd")
const InteractionService = preload("res://scripts/services/interaction_service.gd")
const DialogueService = preload("res://scripts/services/dialogue_service.gd")
const MenuLayer = preload("res://scripts/ui/menu_layer.gd")
var session := SessionService.new()
var actors := ActorController.new()
var world := WorldRegistry.new()
var interactions := InteractionService.new()
var dialogue := DialogueService.new()
var settings: Node
var menus: CanvasLayer
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
	get: return is_shift_active() and not session.roaming() and orders.lifecycle == orders.Lifecycle.ON_ROUTE
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
## Phase 06 placeholder people: they carry no collision and phase 12 replaces
## them, but the conversations are authored against them today.
@onready var shopkeeper: Node3D = get_node_or_null("Shopkeeper") as Node3D
@onready var gossip: Node3D = get_node_or_null("Gossip") as Node3D
@onready var customer: Node3D = get_node_or_null("Customer") as Node3D

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
	interactions.name = "Interactions"
	add_child(interactions)
	dialogue.name = "Dialogue"
	add_child(dialogue)
	orders.shift_ended.connect(_on_shift_ended)
	orders.ticket_created.connect(_on_ticket_created)
	orders.ticket_ready.connect(_on_ticket_ready)
	orders.picked_up.connect(_on_ticket_received)
	hud = $HUD
	presentation.name = "Presentation"
	add_child(presentation)
	sound.name = "Sound"
	add_child(sound)
	hud.snapshot_provider = get_snapshot
	# Preferences exist before any menu is shown and are applied to global
	# systems (audio, window, UI scale, InputMap) by the service itself.
	settings = SettingsService.new()
	settings.name = "Settings"
	add_child(settings)
	settings.configure()
	settings.load_settings()
	menus = MenuLayer.new()
	menus.name = "Menus"
	add_child(menus)
	menus.configure(self, settings)
	menus.menu_action.connect(_on_menu_action)

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
		menus.show_message("WORLD SETUP ERROR", "\n".join(world_errors))
		set_process(false)
		return

	pip.cargo_source = orders
	actors.configure(pip, van, camera, session, balance)
	camera.configure(session, balance)
	sound.configure(van)
	presentation.configure(hud, world, orders, actors, session, balance, sound)
	presentation.interactions = interactions
	interactions.configure(world, actors, dialogue)
	dialogue.configure(world, orders, session, settings, hud)
	dialogue.bind_command("pick_up", _pick_up)
	dialogue.bind_command("deliver", _deliver)
	dialogue.load_all()
	_register_interactions()
	orders.settled.connect(actors.on_settlement)
	pip.footstep.connect(sound.footstep)
	van.honked.connect(sound.honk)
	settings.changed.connect(_on_settings_changed)
	_apply_scene_settings()

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
	if dialogue: dialogue.reset()
	orders.reset(session.generation + 1)
	if world.ready_stock != null:
		world.ready_stock.visible = false
	actors.reset(world.player_spawn, world.van_spawn)
	session.reset()
	_place_customer()


## Clock-free exploration: same town and controls, no ticket, no deadline.
func start_free_roam() -> bool:
	if not world_ready or state != State.TITLE: return false
	if not session.start("roam"): return false
	_place_customer()
	_sync_movement()
	return true


func free_roam() -> bool:
	return session.roaming()


func start_shift() -> bool:
	if not world_ready or state != State.TITLE: return false
	if not session.start(): return false
	_new_order()
	_sync_movement()
	return true


func _start_shift() -> void:
	start_shift()


# ------------------------------------------------------------------ menus and settings
## Esc/back fallback order: menus, then free camera, then pause, then result.
func handle_back() -> bool:
	if menus and menus.handle_back():
		return true
	if camera and camera.is_free():
		camera.exit_free()
		return true
	if is_shift_active():
		session.toggle_pause()
		return true
	if state == State.COMPLETE or state == State.FAILED:
		restart()
		return true
	return false


func _on_menu_action(id: StringName) -> void:
	match id:
		&"start_shift":
			start_shift()
		&"start_roam":
			start_free_roam()
		&"resume":
			if session.paused and &"user_pause" in session.reasons():
				session.close_modal(&"user_pause")
		&"restart_shift":
			# Preserve the chosen mode: a roam restart stays clock-free.
			var roam := session.roaming()
			restart()
			if roam:
				start_free_roam()
			else:
				start_shift()
		&"return_to_title":
			restart()
		&"quit":
			get_tree().quit()


func _on_settings_changed(_key: String) -> void:
	_apply_scene_settings()


## Scene-owned halves of the persisted preferences: sun shadows, ambient
## occlusion/glow on the shipped Environment, camera feel and HUD text pacing.
## Globals (audio/window/shadow filter/AA/input) apply inside SettingsService.
func _apply_scene_settings() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = bool(settings.value("video/shadows"))
		sun.directional_shadow_max_distance = settings.shadow_distance()
	var world_env := get_node_or_null("Environment") as WorldEnvironment
	if world_env and world_env.environment:
		_apply_occlusion(world_env.environment)
		world_env.environment.glow_enabled = bool(settings.value("video/glow"))
	if camera:
		camera.apply_preferences(
			float(settings.value("camera/sensitivity")),
			bool(settings.value("camera/invert_y")),
			bool(settings.value("camera/recenter")),
			bool(settings.value("camera/reduced_motion")))
	if hud:
		hud.text_speed = float(settings.value("text/speed"))
		hud.subtitles = bool(settings.value("text/subtitles"))


## AMBIENT OCCLUSION OFF/LOW/HIGH on the scene's own Environment. The renderer's
## SSAO quality/half-size keys are the cost lever and live in SettingsService.
func _apply_occlusion(environment: Environment) -> void:
	var tier := clampi(int(settings.value("video/ssao")), 0, 2)
	environment.ssao_enabled = tier > 0
	if tier == 0:
		return
	var low := tier == 1
	environment.ssao_radius = 0.8 if low else 1.1
	environment.ssao_detail = 0.25 if low else 0.6
	environment.ssao_intensity = 1.2 if low else 2.0


## Copy shown by the results screen. Itemized from the order ledger.
func results_title() -> String:
	if not world_ready:
		return "WORLD SETUP ERROR"
	return "SHIFT COMPLETE" if session.outcome == "won" else "SHIFT OVER"


func results_body() -> String:
	if not world_ready:
		return "\n".join(world_errors)
	var head := ""
	if session.outcome == "won":
		head = "GOAL REACHED  ·  the island is fed and happy" if strikes == 0 else \
			"GOAL REACHED  ·  %d late drop%s on the way" % [strikes, "" if strikes == 1 else "s"]
	else:
		head = "THREE ORDERS WENT COLD  ·  the clock beat you this time"
	return "%s\nDELIVERIES  %d     STRIKES  %d / %d\nEARNINGS  $%d     base $%d  ·  pizza $%d  ·  tips $%d" % [
		head, deliveries, strikes, max_strikes, money, orders.total_base, orders.total_pizza, orders.total_tip]


# ------------------------------------------------------------------ shift flow
func destination_ids() -> Array[String]:
	return world.ids()


func force_destination_index(index: int) -> bool:
	return orders.force_destination(world.legacy_id(index), world.ids())


func _new_order() -> void:
	if not world_ready or paused or state in [State.COMPLETE, State.FAILED]: return
	orders.create_ticket(destination_ids())


## Customer placement follows the order owner's committed ticket signal. This
## also covers tickets created inside settlement/timeout transactions.
func _on_ticket_created(_event: Dictionary) -> void:
	if world.ready_stock != null:
		world.ready_stock.visible = false
	_place_customer()


func _on_ticket_ready(_event: Dictionary) -> void:
	if world.ready_stock == null:
		return
	world.ready_stock.visible = true
	for index in range(world.ready_stock.get_child_count()):
		world.ready_stock.get_child(index).visible = index < orders.pizzas


func _on_ticket_received(_event: Dictionary) -> void:
	if world.ready_stock != null:
		world.ready_stock.visible = false
	if shopkeeper != null and shopkeeper.has_method("play_handoff"):
		shopkeeper.play_handoff()


## Commit targets of the counter and door conversations. A conversation runs on
## top of a paused world, so a commit is accepted while one is open - an ordinary
## menu pause still refuses it.
func _pick_up() -> bool:
	if not is_shift_active() or driving or (paused and not talking()):
		return false
	return orders.pickup()


func _deliver() -> bool:
	if not is_shift_active() or driving or (paused and not talking()):
		return false
	return orders.settle(destination_ids(), _generation, orders.order_id)


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
		if not session.roaming():
			orders.tick(delta, destination_ids())
		if is_shift_active(): presentation.update_context()


func _current_tip() -> int:
	return orders.tip()


func _context() -> void:
	presentation.update_context()


## True while a conversation owns gameplay input.
func talking() -> bool:
	return dialogue != null and dialogue.active()


## One press reaches the world only when no menu owns the keys. A conversation is
## allowed to keep the interact key while the world is paused for it, but the
## pause menu stacked above it takes the keys back.
func interact_available() -> bool:
	if not is_shift_active():
		return false
	if not paused:
		return true
	return talking() and not (&"user_pause" in session.reasons())


func interact() -> void:
	if not interact_available():
		return
	# One press opens exactly one conversation and the next press drives it: the
	# same key can never skip a line and start an action in the same frame.
	if talking():
		dialogue.advance()
		return
	interactions.activate()


func _on_interact() -> void:
	interact()


func force_destination(id: String) -> bool:
	return orders.force_destination(id, world.ids())


# ------------------------------------------------------------------ interactions
## Milestone A: every target is registered once with its own anchor, access point,
## gate and blocked reason. The HUD prompt and the accepted action both come from
## this table, so they cannot disagree about range, facing, access or actor mode.
func _register_interactions() -> void:
	interactions.clear()
	_place_shopkeeper()
	_register_counter()
	_register_customer()
	_register_van()
	_register_gossip()


## The counter is the shopkeeper by the service window behind the pick-up point.
func _place_shopkeeper() -> void:
	if shopkeeper == null:
		return
	var station: Node3D = world.staff_station if world.staff_station != null else pickup_point
	if station == null:
		return
	shopkeeper.global_position = station.global_position + Vector3(0, -0.08, 0)
	var entrance: Vector3 = world.shop_entrance.global_position if world.shop_entrance != null else station.global_position + Vector3(0, 0, -1)
	shopkeeper.look_at(Vector3(entrance.x, shopkeeper.global_position.y + 1.0, entrance.z), Vector3.UP)


## The customer waits outside the ordered house for the whole shift, on the side
## of the door away from the van pad (the pad is `side * 2.75` in house space).
func _place_customer() -> void:
	if customer == null:
		return
	if not is_shift_active() or session.roaming() or order_house == null:
		customer.visible = false
		return
	var door := order_house.get_node_or_null("Door") as Node3D
	if door == null:
		customer.visible = false
		return
	var basis := order_house.global_transform.basis
	var outward := basis.z * (1.0 if door.position.z >= 0.0 else -1.0)
	var park := order_house.get_node_or_null("Park") as Node3D
	var side := 1.0 if (park == null or park.position.x >= 0.0) else -1.0
	var here := door.global_position
	var spot := here + outward * 0.95 + basis.x * (-side * 0.95)
	customer.global_position = Vector3(spot.x, here.y - 0.02, spot.z)
	customer.look_at(Vector3(here.x + outward.x * 6.0, customer.global_position.y, here.z + outward.z * 6.0), Vector3.UP)
	customer.visible = true


func _counter_open() -> bool:
	if not is_shift_active() or session.roaming():
		return false
	return orders.lifecycle == orders.Lifecycle.AT_SHOP and orders.cargo_count == 0


func _counter_reason() -> String:
	if session.roaming():
		return "COUNTER CLOSED"
	if orders.cargo_count > 0 or orders.lifecycle == orders.Lifecycle.ON_ROUTE:
		return "HANDS FULL"
	return "ORDER ALREADY TAKEN"


func _register_counter() -> void:
	if shopkeeper == null or world.counter_access == null:
		return
	interactions.register({
		"id": &"shop.counter",
		"anchor": world.counter_access,
		"range": 2.0,
		"priority": 30,
		"modes": [ActorController.Mode.FOOT],
		"facing": 60.0,
		"view": 1.15,
		"label": func() -> String: return "CHECK TICKET" if orders.ticket_state == orders.TicketState.PREPARING else "TAKE THE ORDER",
		"enabled": _counter_open,
		"reason": _counter_reason,
		"on_activate": func(_service: Node) -> bool: return _talk("shopkeeper", &"shop.counter"),
	})


func _register_customer() -> void:
	if customer == null:
		return
	# No facing gate here: the customer stands beside the door, so a player who
	# walks up to it and looks at the house must still reach the handoff - and the
	# priority below keeps the parked van's door from stealing that press.
	interactions.register({
		"id": &"house.customer",
		"anchor": customer,
		"access": Vector3(0, 0, -0.75),
		"range": 3.0,
		"priority": 35,
		"active": func() -> bool: return is_shift_active() and not session.roaming(),
		"label": func() -> String: return "DELIVER %d %s" % [orders.pizzas, "PIZZA" if orders.pizzas == 1 else "PIZZAS"],
		"enabled": func() -> bool: return orders.lifecycle == orders.Lifecycle.ON_ROUTE \
			and orders.cargo_count > 0 and orders.cargo_count == orders.pizzas,
		"reason": func() -> String: return "NOTHING TO DELIVER" if orders.cargo_count == 0 else "WRONG ORDER",
		"on_activate": func(_service: Node) -> bool: return _talk("customer", &"house.customer"),
	})


## Two entries on the same van - the driver door from outside, the seat from
## inside - prove the mode gate and the tie-break, and keep the old prompt copy.
func _register_van() -> void:
	interactions.register({
		"id": &"van.driver",
		"anchor": van,
		"access": Vector3(1.35, 0, -0.35),
		"range": 2.6,
		"priority": 25,
		"modes": [ActorController.Mode.FOOT],
		"label": func() -> String: return "DRIVE",
		"enabled": func() -> bool: return actors.stopped(),
		"reason": func() -> String: return "WAIT FOR THE VAN TO STOP",
		"on_activate": func(_service: Node) -> bool: return _enter_van(),
	})
	interactions.register({
		"id": &"van.seat",
		"anchor": van,
		"access": Vector3(0, 0, 0),
		"range": 1.0,
		"priority": 25,
		"modes": [ActorController.Mode.DRIVING],
		"label": func() -> String: return "HOP OUT",
		"enabled": func() -> bool: return actors.stopped(),
		"reason": func() -> String: return "STOP THE VAN TO EXIT",
		"on_activate": func(_service: Node) -> bool: return _exit_van(),
	})


## Ambient neighbour: the optional conversation that may be cancelled freely.
func _register_gossip() -> void:
	if gossip == null:
		return
	interactions.register({
		"id": &"plaza.gossip",
		"anchor": gossip,
		"access": Vector3(0, 0, -0.75),
		"range": 2.8,
		"facing": 75.0,
		"priority": 10,
		"active": func() -> bool: return is_shift_active(),
		"label": func() -> String: return "CHAT",
		"on_activate": func(_service: Node) -> bool: return _talk("gossip", &"plaza.gossip"),
	})


## Opens a conversation for the target that won the query.
func _talk(conversation: String, busy: StringName) -> bool:
	var anchor: Node3D = null
	match busy:
		&"shop.counter":
			anchor = shopkeeper
		&"house.customer":
			anchor = customer
		&"plaza.gossip":
			anchor = gossip
	return dialogue.start(conversation, busy, anchor)


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
		"ticket_state": orders.ticket_state_name(),
		"preparation_remaining": orders.preparation_remaining,
		"ticket_customer": str(order_house.get_meta("label", "")) if order_house else "",
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
		"play_mode": session.mode,
		"gameplay_visible": session.flow == session.Flow.PLAYING,
		"menu_screen": menus.top_id() if menus else "",
		"menu_focused": menus.focused_id() if menus else "",
		"actor_mode": "driving" if driving else "foot",
		"order_lifecycle": ["idle", "at_shop", "on_route", "closed"][orders.lifecycle],
		"ticket_state": orders.ticket_state_name(), "preparation_remaining": orders.preparation_remaining,
		"goal_money": goal_money, "timer_visible": timer_visible, "speed_kmh": speed_kmh,
		"objective_text": objective_text, "target_label": target_label, "target_sub": target_sub,
		"prompt_text": prompt_text, "waypoint_visible": waypoint_visible,
		"waypoint_position": waypoint_position, "waypoint_color": waypoint_color,
		"prompt_id": str(presentation.prompt_id),
		"camera_mode": camera.mode_name() if camera else "title",
		"camera_hint": camera.free_camera_hint() if camera else "",
		"total_base": orders.total_base, "total_pizza": orders.total_pizza, "total_tip": orders.total_tip,
		"actor_position": (van.global_position if driving else pip.global_position) if world_ready else Vector3.ZERO,
	})
	if dialogue != null:
		values.merge(dialogue.snapshot())
	return Snapshot.new(values)


func get_diagnostics() -> Dictionary:
	return get_snapshot().to_dictionary()
