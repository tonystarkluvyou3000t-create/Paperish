extends Node3D
## Pip the Pizza Boy - the shift.
## Take the order, grab the pizzas at the shop, drive to the address, park, hop
## out and deliver on foot before the clock runs out. Three timeouts end the day.

enum State { TITLE, TO_SHOP, TO_HOUSE, COMPLETE, FAILED }

## Shared pause reason for the town map screen (menu_layer maps it to the screen).
const MAP_MODAL := &"map"

const Snapshot = preload("res://scripts/services/game_snapshot.gd")
const Presentation = preload("res://scripts/services/presentation.gd")
const SoundPresenter = preload("res://scripts/services/sound_presenter.gd")
var presentation := Presentation.new()
var sound := SoundPresenter.new()
const OrderService = preload("res://scripts/services/order_service.gd")
const CargoService = preload("res://scripts/services/cargo_service.gd")
const RouteService = preload("res://scripts/services/route_service.gd")
const Balance = preload("res://scripts/services/balance.gd")
@export var balance: Balance = preload("res://data/balance.tres")
var orders := OrderService.new()
var cargo := CargoService.new()
var routes := RouteService.new()
var _nav_order_ids: Array[int] = []
var _nav_warning := ""
var _map_model: Dictionary = {}
const SessionService = preload("res://scripts/services/session_service.gd")
const MapModel = preload("res://scripts/ui/map_model.gd")
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
var _customer_actors: Dictionary = {}
var _dialogue_order_id := 0
var _dialogue_customer_id := ""
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
	cargo.name = "Cargo"
	cargo.configure(van, balance.van_capacity, balance.player_carry_capacity)
	add_child(cargo)
	orders.cargo_service = cargo
	orders.route_estimator = Callable(self, "_estimate_route_seconds")
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
	cargo.changed.connect(_on_cargo_changed)
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

	pip.cargo_source = cargo
	actors.configure(pip, van, camera, session, balance)
	camera.configure(session, balance)
	routes.configure(world.graph, balance)
	routes.route_changed.connect(_on_route_changed)
	_map_model.clear()
	hud.map_model = map_model()
	sound.configure(van)
	presentation.configure(hud, world, orders, actors, session, balance, sound)
	presentation.interactions = interactions
	interactions.configure(world, actors, dialogue)
	dialogue.configure(world, orders, session, settings, hud)
	dialogue.bind_command("pick_up", _pick_up)
	dialogue.bind_command("deliver", _deliver)
	dialogue.bind_command("queue", _queue_order)
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
	_clear_order_customers()
	_dialogue_order_id = 0
	_dialogue_customer_id = ""
	orders.reset(session.generation + 1)
	if world.ready_stock != null:
		world.ready_stock.visible = false
	actors.reset(world.player_spawn, world.van_spawn)
	routes.clear("restart")
	routes.set_waypoint(null)
	_nav_order_ids.clear()
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
		&"open_map":
			open_map()
		&"close_map":
			close_map()
		&"unstuck":
			unstuck()
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
	return "%s\nDELIVERIES  %d     STRIKES  %d / %d\nEARNINGS  $%d     base $%d  ·  pizza $%d  ·  tips $%d  ·  quality %d" % [
		head, deliveries, strikes, max_strikes, money, orders.total_base, orders.total_pizza, orders.total_tip, orders.total_quality]


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
	_refresh_order_customers()


func _on_ticket_ready(_event: Dictionary) -> void:
	if int(_event.get("order_id", -1)) == orders.order_id:
		_sync_selected_stock()


func _sync_selected_stock() -> void:
	if world.ready_stock == null:
		return
	var ready := orders.lifecycle == orders.Lifecycle.AT_SHOP and orders.ticket_state == orders.TicketState.READY
	world.ready_stock.visible = ready
	for index in range(world.ready_stock.get_child_count()):
		world.ready_stock.get_child(index).visible = ready and index < orders.pizzas


func _on_ticket_received(_event: Dictionary) -> void:
	if world.ready_stock != null:
		world.ready_stock.visible = false
	if shopkeeper != null and shopkeeper.has_method("play_handoff"):
		shopkeeper.play_handoff()
	_refresh_order_customers()


## Commit targets of the counter and door conversations. A conversation runs on
## top of a paused world, so a commit is accepted while one is open - an ordinary
## menu pause still refuses it.
func _pick_up() -> bool:
	if not is_shift_active() or driving or (paused and not talking()):
		return false
	return orders.pickup()


func _queue_order() -> bool:
	if not is_shift_active() or driving or not talking():
		return false
	var accepted := orders.queue_ticket(destination_ids(), false)
	if accepted:
		hud.caption("TICKET QUEUED · UP TO THREE ORDERS")
	return accepted


func _deliver() -> bool:
	if not is_shift_active() or driving or (paused and not talking()):
		return false
	var order := _dialogue_order_id if _dialogue_order_id > 0 else orders.order_id
	var customer_id := _dialogue_customer_id if not _dialogue_customer_id.is_empty() \
		else orders.destination_for_order(order)
	var settled_ok := orders.settle_order(destination_ids(), _generation, order, customer_id)
	if settled_ok:
		_refresh_order_customers()
	return settled_ok


func _on_timeout() -> void:
	if is_shift_active() and not paused:
		if orders.expire(destination_ids(), _generation, orders.order_id):
			_refresh_order_customers()


func _on_shift_ended(event: Dictionary) -> void:
	_finish(event.outcome == "won")


func _finish(win: bool) -> void:
	if not is_shift_active() or paused: return
	orders.close()
	session.finish(win)


func _process(delta: float) -> void:
	if not world_ready or paused: return
	if is_shift_active():
		if Input.is_action_just_pressed("cargo_cycle") and not driving and _near_cargo_door():
			var selected := cargo.select_next_van_order()
			if selected > 0:
				orders.select_order(selected)
				hud.caption("SELECTED ORDER #%02d" % selected)
		if not session.roaming():
			var before := orders.outstanding_order_ids()
			orders.tick(delta, destination_ids())
			if before != orders.outstanding_order_ids():
				_refresh_order_customers()
			_sync_selected_stock()
		if is_shift_active(): presentation.update_context()
	_sync_navigation(delta)


# ------------------------------------------------------------------ navigation
## Route + guidance upkeep. The target follows the selected ticket, the stop plan
## follows the outstanding tickets (in the player's own order) and the route
## service decides for itself when a recompute is meaningful. Runs only while
## gameplay is live, never while paused or talking, so guidance can never tick a
## deadline forward behind a modal.
func _sync_navigation(delta: float) -> void:
	if not world_ready:
		return
	var outstanding := orders.outstanding_order_ids()
	if outstanding != _nav_order_ids:
		_nav_order_ids = outstanding.duplicate()
		var stops: Array = []
		for id in outstanding:
			var address := orders.destination_for_order(id)
			if address.is_empty():
				continue
			stops.append({"order_id": id, "address_id": address})
		routes.set_stops(stops)
	var destination := ""
	if orders.lifecycle == OrderService.Lifecycle.ON_ROUTE:
		destination = orders.destination_id
	routes.set_target(destination)
	routes.update(delta, driving, van.global_position, pip.global_position)


## The town map is a shared modal: it consumes gameplay input and pauses the
## simulation while it is up, exactly like the options and dialogue screens.
func open_map() -> bool:
	if not is_shift_active() or talking():
		return false
	return session.open_modal(MAP_MODAL)


func close_map() -> bool:
	return session.close_modal(MAP_MODAL)


func map_open() -> bool:
	return session.paused and MAP_MODAL in session.reasons()


func navigation_mode() -> String:
	if settings == null:
		return "map"
	var mode := str(settings.value("hud/navigation"))
	return mode if mode in ["map", "compass", "off"] else "map"


## Route polylines as plain points for the HUD map and the map screen.
func route_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var route: Dictionary = routes.route()
	if not bool(route.get("reachable", false)):
		return points
	for point in route.get("drive_points", []):
		points.append(point)
	var walk: Array = route.get("walk_points", [])
	for index in range(1, walk.size()):
		points.append(walk[index])
	return points


## Returns the player to a validated road anchor. Cargo is never touched and no
## delivery settles: in a timed shift the cost is transparent time off each
## running delivery (floored so a rescue can never itself cause a timeout), while
## clock-free roam and untimed phases pay nothing.
func unstuck() -> bool:
	if not world_ready or not is_shift_active():
		return false
	var anchors: Array = world.graph.layout.get("recovery_anchors", [])
	if anchors.is_empty():
		return false
	var driving_now := driving
	var actor_position: Vector3 = van.global_position if driving_now else pip.global_position
	var best: Dictionary = {}
	var best_distance := INF
	for anchor in anchors:
		var row: Array = anchor.position
		var distance := actor_position.distance_to(Vector3(float(row[0]), 0.0, float(row[1])))
		if distance < best_distance:
			best_distance = distance
			best = anchor
	if best.is_empty():
		return false
	var row: Array = best.position
	var target := Vector3(float(row[0]), actor_position.y, float(row[1]))
	# Face along a legal lane so the van resumes road-legal, not across a kerb.
	var entry: Dictionary = world.graph.nearest_legal_entry(target)
	var yaw := (van.rotation.y if driving_now else pip.rotation.y)
	if bool(entry.get("reachable", false)):
		var lane: Dictionary = world.graph.lane_data(str(entry.get("lane_id", "")))
		if not lane.is_empty():
			yaw = deg_to_rad(float(lane.get("yaw_deg", 0.0)))
	if driving_now:
		van.global_position = target
		van.rotation.y = yaw
	else:
		pip.global_position = target
		pip.rotation.y = yaw
	_cancel_motion()
	var cost := 0.0
	if not session.roaming():
		cost = orders.apply_recovery_cost(float(balance.unstuck_time_cost),
			float(balance.unstuck_min_remaining))
	hud.caption("BACK ON THE ROAD" + ("  ·  −%d S" % roundi(cost) if cost > 0.0 else "  ·  NO CHARGE"))
	return true


func unstuck_available() -> bool:
	return is_shift_active() and world_ready


func unstuck_label() -> String:
	var base := "UNSTUCK  ·  BACK TO THE ROAD"
	if session.roaming():
		return base + "  ·  NO TIMER"
	if orders.lifecycle == OrderService.Lifecycle.ON_ROUTE:
		return base + "  ·  −%d S" % roundi(balance.unstuck_time_cost)
	return base


# ------------------------------------------------------------------ map screen
## Static map layers, built once from the same catalog that generates the town.
func map_model() -> Dictionary:
	if _map_model.is_empty() and world_ready:
		_map_model = MapModel.build(world.graph.layout)
	return _map_model if not _map_model.is_empty() else MapModel.build({})


## Live state for the map renderer: actors, route polyline, ticket markers and
## the player's waypoint. Safe to call while the world is paused.
func map_view_state() -> Dictionary:
	var state := {
		"driving": driving,
		"player": Vector2(pip.global_position.x, pip.global_position.z),
		"player_yaw": pip.rotation.y,
		"van": Vector2(van.global_position.x, van.global_position.z),
		"van_yaw": van.rotation.y,
	}
	if not world_ready:
		return state
	state["route"] = route_points()
	var route: Dictionary = routes.route()
	state["route_drive_count"] = int(route.get("drive_points", []).size())
	state["target"] = _marker_for(routes.target())
	var tickets: Array = []
	for stop in routes.stops():
		var marker: Variant = _marker_for(str(stop.address_id))
		if marker != null:
			tickets.append({"position": marker, "selected": int(stop.order_id) == orders.order_id})
	if not tickets.is_empty():
		state["tickets"] = tickets
	if routes.has_waypoint():
		state["waypoint"] = routes.waypoint()
	return state


## Ticket rows for the map's stop list, in the player's own plan order. Each row
## carries the leg estimate, the running arrival estimate and the remaining
## window so the player can compare them; nothing is re-ordered for the player.
func map_ticket_rows() -> Array:
	var rows: Array = []
	if not world_ready:
		return rows
	var remaining := {}
	for id in orders.outstanding_order_ids():
		remaining[id] = float(orders.order_data(id).get("remaining", 0.0))
	for row in routes.stop_estimates(van.global_position, remaining):
		var order_id := int(row.order_id)
		var data: Dictionary = orders.order_data(order_id)
		var address := str(data.get("destination_id", ""))
		var record: Dictionary = world.graph.address_data(address)
		var collected: bool = int(data.get("lifecycle", -1)) == OrderService.Lifecycle.ON_ROUTE
		rows.append({
			"order_id": order_id, "address": address,
			"district": str(record.get("district_id", "")), "district_name": str(record.get("district_id", "")),
			"state": orders.lifecycle_name(order_id),
			"cargo": "%s  ·  %d PIZZA%s" % [str(data.get("cargo_location", "")).to_upper(),
				int(data.get("quantity", 0)), "" if int(data.get("quantity", 0)) == 1 else "S"],
			"pizzas": int(data.get("quantity", 0)),
			"reachable": bool(row.reachable), "reason": str(row.reason),
			"leg_seconds": float(row.leg_seconds), "cumulative_seconds": float(row.cumulative_seconds),
			"window_seconds": float(data.get("remaining", 0.0)) if collected else float(data.get("duration", 0.0)),
			"window_active": collected,
			"slack_seconds": float(row.get("slack_seconds", -INF)) if collected else -INF,
			"selected": order_id == orders.order_id,
		})
	return rows


## Select the ticket the HUD and the route follow.
func map_select_order(order_id: int) -> bool:
	if not orders.select_order(order_id):
		return false
	hud.caption("ROUTE TIED TO ORDER #%02d" % order_id)
	presentation.update_context()
	return true


## Reorder one stop in the player's plan: up is -1, down is +1.
func map_move_stop(order_id: int, delta: int) -> bool:
	if not routes.move_stop(order_id, delta):
		return false
	hud.caption("STOP ORDER %s" % _plan_ids_text())
	return true


func map_set_waypoint(world_position: Vector2) -> void:
	routes.set_waypoint(world_position)
	hud.caption("WAYPOINT SET")


func map_clear_waypoint() -> void:
	routes.clear_waypoint()
	hud.caption("WAYPOINT CLEARED")


func _marker_for(address: String) -> Variant:
	if address.is_empty():
		return null
	var row: Dictionary = world.graph.address_data(address)
	var door: Array = row.get("door_position", [])
	if door.size() < 2:
		return null
	return Vector2(float(door[0]), float(door[1]))


## Where guidance is currently sending the player: the next maneuver point when
## one is due, else the end of the active leg.
func _nav_target_point(guidance: Dictionary) -> Vector3:
	var maneuver: Dictionary = guidance.get("maneuver", {})
	if not maneuver.is_empty():
		return maneuver.get("at", Vector3.ZERO)
	var route: Dictionary = routes.route()
	if str(guidance.get("leg", "")) == "walk":
		return route.get("door_position", Vector3.ZERO)
	return route.get("park_position", Vector3.ZERO)


## One notification per blocked situation: recomputes do not spam captions.
func _on_route_changed(event: Dictionary) -> void:
	if bool(event.get("reachable", false)):
		_nav_warning = ""
		return
	var address := str(event.get("address_id", ""))
	if address.is_empty():
		_nav_warning = ""
		return
	var detail := str(event.get("detail", ""))
	var warning := address + "|" + detail
	if warning == _nav_warning:
		return
	_nav_warning = warning
	hud.toast("NO ROUTE  ·  %s" % address.to_upper())
	presentation.update_context()


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
	_register_house_doors()
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
	for id in orders.outstanding_order_ids():
		var actor: Node3D = _customer_actors.get(id)
		if actor != null:
			_place_customer_actor(id, actor)


func _refresh_order_customers() -> void:
	if not is_instance_valid(customer):
		return
	var active := orders.outstanding_order_ids()
	for key in _customer_actors.keys().duplicate():
		var id := int(key)
		if id in active:
			continue
		interactions.unregister(_customer_interaction_id(id))
		var old: Node3D = _customer_actors[id]
		_customer_actors.erase(id)
		if old == customer:
			old.visible = false
		else:
			old.queue_free()
	for id in active:
		var actor: Node3D = _customer_actors.get(id)
		if actor == null:
			if _customer_actors.is_empty():
				actor = customer
			else:
				actor = Node3D.new()
				actor.name = "OrderCustomer_%02d" % id
				actor.set_script(preload("res://scripts/npc_placeholder.gd"))
				add_child(actor)
			_customer_actors[id] = actor
		_place_customer_actor(id, actor)
		_register_customer_for(id, actor)
	_place_customer()


func _clear_order_customers() -> void:
	for id in _customer_actors.keys():
		interactions.unregister(_customer_interaction_id(int(id)))
		var actor: Node3D = _customer_actors[id]
		if actor != customer and is_instance_valid(actor):
			actor.queue_free()
	_customer_actors.clear()
	if is_instance_valid(customer):
		customer.visible = false


func _place_customer_actor(order: int, actor: Node3D) -> void:
	var house := world.destination(orders.destination_for_order(order))
	if not is_shift_active() or session.roaming() or house == null:
		actor.visible = false
		return
	var door := house.get_node_or_null("Door") as Node3D
	if door == null:
		actor.visible = false
		return
	var customer_slot := house.get_node_or_null("CustomerSlot") as Node3D
	var basis := house.global_transform.basis
	var outward := basis.z * (1.0 if door.position.z >= 0.0 else -1.0)
	var park := house.get_node_or_null("Park") as Node3D
	var side := 1.0 if (park == null or park.position.x >= 0.0) else -1.0
	var here := door.global_position
	var spot := customer_slot.global_position if customer_slot != null else here + outward * 0.95 + basis.x * (-side * 0.95)
	actor.global_position = Vector3(spot.x, here.y - 0.02, spot.z)
	actor.look_at(Vector3(here.x + outward.x * 6.0, actor.global_position.y, here.z + outward.z * 6.0), Vector3.UP)
	actor.visible = true


func _counter_open() -> bool:
	if not is_shift_active() or session.roaming():
		return false
	return orders.lifecycle == orders.Lifecycle.AT_SHOP or orders.can_pickup() or orders.can_queue(destination_ids())


func _counter_reason() -> String:
	if session.roaming():
		return "COUNTER CLOSED"
	if orders.order_count() >= balance.max_queued_orders:
		return "TICKET BOARD FULL"
	if cargo.count_at(CargoService.COUNTER) + cargo.count_at(CargoService.PIP) + cargo.count_at(CargoService.VAN) >= cargo.van_capacity:
		return "VAN CAPACITY FULL"
	return "NO READY TICKET"


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
		"label": func() -> String:
			if orders.lifecycle == orders.Lifecycle.ON_ROUTE:
				return "QUEUE ANOTHER ORDER"
			return "CHECK TICKET" if orders.ticket_state == orders.TicketState.PREPARING else "TAKE THE ORDER",
		"enabled": _counter_open,
		"reason": _counter_reason,
		"on_activate": func(_service: Node) -> bool: return _talk("shopkeeper", &"shop.counter"),
	})


func _register_customer() -> void:
	if orders.outstanding_order_ids().is_empty() and is_instance_valid(customer):
		_register_customer_for(1, customer)
	else:
		_refresh_order_customers()


func _register_house_doors() -> void:
	for house in world.houses:
		_register_house_door(house)


func _register_house_door(house: Node3D) -> void:
	var address := str(house.get_meta("address", ""))
	var door := house.get_node_or_null("Door") as Node3D
	if door == null or address.is_empty():
		return
	var outside_sign := 1.0 if door.position.z >= 0.0 else -1.0
	interactions.register({
		"id": _house_door_interaction_id(address),
		"anchor": door,
		"access": Vector3(0, 0, outside_sign * 1.15),
		"range": 2.7,
		"priority": 12,
		"modes": [ActorController.Mode.FOOT],
		"active": func() -> bool: return _has_route_order(),
		"label": "RING DOORBELL",
		"enabled": _has_pip_order,
		"reason": func() -> String: return "NOTHING TO HAND OVER" if cargo.count_at(CargoService.PIP) == 0 else "WRONG ADDRESS",
		"on_activate": func(_service: Node) -> bool: return _talk_wrong_address(address, door),
	})


func _has_route_order() -> bool:
	for id in orders.outstanding_order_ids():
		if orders.lifecycle_name(id) == "on_route":
			return true
	return false


func _has_pip_order() -> bool:
	return _has_route_order() and cargo.count_at(CargoService.PIP) > 0


func _house_door_interaction_id(address: String) -> StringName:
	return StringName("house.door." + address.to_lower().replace(" ", "_").replace(".", ""))


func _talk_wrong_address(address: String, door: Node3D) -> bool:
	var carrying: Array[int] = []
	for id in orders.outstanding_order_ids():
		if cargo.location_for_order(id) == CargoService.PIP:
			carrying.append(id)
	if carrying.is_empty():
		return false
	var id := carrying[0]
	orders.select_order(id)
	_dialogue_order_id = id
	_dialogue_customer_id = address
	return dialogue.start("wrong_address", _house_door_interaction_id(address), door)


func _register_customer_for(order: int, actor: Node3D) -> void:
	if actor == null:
		return
	var id := _customer_interaction_id(order)
	interactions.register({
		"id": id,
		"anchor": actor,
		"access": Vector3(0, 0, -0.75),
		"range": 3.0,
		"priority": 35,
		"active": func() -> bool: return is_shift_active() and not session.roaming(),
		"label": func() -> String:
			var data := orders.order_data(order)
			var quantity := int(data.get("quantity", 0))
			if orders.outstanding_order_ids().size() == 1:
				return "DELIVER %d %s" % [quantity, "PIZZA" if quantity == 1 else "PIZZAS"]
			return "DELIVER #%02d  ·  %d %s" % [order, quantity, "PIZZA" if quantity == 1 else "PIZZAS"],
		"enabled": func() -> bool: return _customer_ready(order),
		"reason": func() -> String: return _customer_reason(order),
		"on_activate": func(_service: Node) -> bool: return _talk_customer(order, actor),
	})


func _customer_ready(order: int) -> bool:
	var data := orders.order_data(order)
	return not data.is_empty() and str(data.get("lifecycle_name", "")) == "on_route" \
		and str(data.get("cargo_location", "")) == CargoService.PIP \
		and int(data.get("cargo_count", 0)) == int(data.get("quantity", 0)) \
		and float(data.get("remaining", 0.0)) > 0.0


func _customer_reason(order: int) -> String:
	var data := orders.order_data(order)
	if data.is_empty():
		return "ORDER NOT READY"
	if str(data.get("lifecycle_name", "")) != "on_route":
		return "NOTHING TO DELIVER"
	match str(data.get("cargo_location", "")):
		CargoService.VAN: return "UNLOAD ORDER #%02d AT THE VAN" % order
		CargoService.COUNTER: return "TAKE THE ORDER FROM MONA"
		CargoService.PIP: return "WRONG ORDER"
		_: return "NOTHING TO DELIVER"


func _talk_customer(order: int, actor: Node3D) -> bool:
	var data := orders.order_data(order)
	if data.is_empty() or not _customer_ready(order):
		return false
	var destination := str(data.get("destination_id", ""))
	if not orders.select_order(order):
		return false
	_dialogue_order_id = order
	_dialogue_customer_id = destination
	return dialogue.start("customer", _customer_interaction_id(order), actor)


func _customer_interaction_id(order: int) -> StringName:
	return &"house.customer" if order == 1 else StringName("house.customer.%02d" % order)


## Two entries on the same van - the driver door from outside, the seat from
## inside - prove the mode gate and the tie-break, and keep the old prompt copy.
func _register_van() -> void:
	var cargo_access := Vector3(0, 0, -2.45)
	interactions.register({
		"id": &"van.cargo.load",
		"anchor": van,
		"access": cargo_access,
		"range": 3.1,
		"priority": 29,
		"modes": [ActorController.Mode.FOOT],
		"label": func() -> String: return "LOAD ORDER #%02d" % orders.order_id,
		"enabled": _can_load_selected,
		"reason": _cargo_block_reason,
		"on_activate": func(_service: Node) -> bool: return _load_selected_bundle(),
	})
	interactions.register({
		"id": &"van.cargo.unload",
		"anchor": van,
		"access": cargo_access,
		"range": 3.1,
		"priority": 28,
		"modes": [ActorController.Mode.FOOT],
		"label": func() -> String: return "TAKE ORDER #%02d" % cargo.selected_van_order,
		"enabled": _can_unload_selected,
		"reason": _cargo_block_reason,
		"on_activate": func(_service: Node) -> bool: return _unload_selected_bundle(),
	})
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


func _can_load_selected() -> bool:
	return not driving and actors.stopped() and orders.order_id > 0 \
		and cargo.location_for_order(orders.order_id) == CargoService.PIP \
		and cargo.count_for_order(orders.order_id, [CargoService.PIP]) <= cargo.van_capacity - cargo.count_at(CargoService.VAN)


func _can_unload_selected() -> bool:
	var order := cargo.selected_van_order
	return not driving and actors.stopped() and order > 0 \
		and cargo.location_for_order(order) == CargoService.VAN \
		and cargo.count_for_order(order, [CargoService.VAN]) <= cargo.player_capacity - cargo.count_at(CargoService.PIP)


func _cargo_block_reason() -> String:
	if not actors.stopped():
		return "STOP THE VAN FIRST"
	if cargo.selected_van_order > 0 and cargo.location_for_order(cargo.selected_van_order) == CargoService.VAN \
			and cargo.count_for_order(cargo.selected_van_order, [CargoService.VAN]) > cargo.player_capacity - cargo.count_at(CargoService.PIP):
		return "HANDS FULL · TAKE A SMALLER ORDER"
	if orders.order_id <= 0 or cargo.location_for_order(orders.order_id) != CargoService.PIP:
		return "NO HELD ORDER TO LOAD"
	return "VAN CARGO IS FULL"


func _load_selected_bundle() -> bool:
	var order := orders.order_id
	if not _can_load_selected() or not cargo.transfer_order(order, CargoService.PIP, CargoService.VAN):
		return false
	cargo.selected_van_order = order
	return true


func _unload_selected_bundle() -> bool:
	var order := cargo.selected_van_order
	if not _can_unload_selected() or not cargo.transfer_order(order, CargoService.VAN, CargoService.PIP):
		return false
	orders.select_order(order)
	return true


func _cargo_door_position() -> Vector3:
	return van.global_transform * Vector3(0, 0, -2.45) if van != null else Vector3.ZERO


func _near_cargo_door() -> bool:
	return pip != null and pip.global_position.distance_to(_cargo_door_position()) <= 3.2


func _on_cargo_changed(_event: Dictionary) -> void:
	if is_instance_valid(pip):
		pip.set_carrying(cargo.count_at(CargoService.PIP))
	_refresh_order_customers()


func _on_order_closed(_event: Dictionary) -> void:
	_refresh_order_customers()


func _estimate_route_seconds(destination: String) -> float:
	if world == null or world.address(destination) == null:
		return INF
	var start := world.shop_entrance.global_position if world.shop_entrance != null else van.global_position
	return routes.estimate_from(start, destination)


func set_order_seed(value: int) -> void:
	orders.set_seed(value)


func _plan_ids_text() -> String:
	var parts := PackedStringArray()
	for stop in routes.stops():
		parts.append(str(int(stop.order_id)))
	return ",".join(parts)


## House-door markers for every outstanding ticket: the minimap shows accepted
## jobs, not just the selected one.
func _ticket_positions() -> PackedVector3Array:
	var points := PackedVector3Array()
	if not world_ready:
		return points
	for stop in routes.stops():
		var marker: Variant = _marker_for(str(stop.address_id))
		if marker != null:
			points.append(Vector3(marker.x, 0.0, marker.y))
	return points


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
	var guidance: Dictionary = routes.guidance()
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
		"order_count": orders.order_count(), "cargo_inventory": orders.inventory_lines(),
		"van_cargo_count": cargo.count_at(CargoService.VAN), "van_capacity": cargo.van_capacity,
		"goal_money": goal_money, "timer_visible": timer_visible, "speed_kmh": speed_kmh,
		"objective_text": objective_text, "target_label": target_label, "target_sub": target_sub,
		"prompt_text": prompt_text, "waypoint_visible": waypoint_visible,
		"waypoint_position": waypoint_position, "waypoint_color": waypoint_color,
		"prompt_id": str(presentation.prompt_id),
		"camera_mode": camera.mode_name() if camera else "title",
		"camera_hint": camera.free_camera_hint() if camera else "",
		"total_base": orders.total_base, "total_pizza": orders.total_pizza, "total_tip": orders.total_tip,
		"actor_position": (van.global_position if driving else pip.global_position) if world_ready else Vector3.ZERO,
		"van_position": van.global_position if world_ready else Vector3.ZERO,
		"van_yaw": van.rotation.y if world_ready else 0.0,
		"actor_yaw": (van.rotation.y if driving else pip.rotation.y) if world_ready else 0.0,
		"nav_mode": navigation_mode(),
		"nav_hint": str(guidance.get("hint", "")), "nav_detail": str(guidance.get("detail", "")),
		"nav_leg": str(guidance.get("leg", "")), "nav_reachable": bool(guidance.get("reachable", false)),
		"nav_remaining_m": float(guidance.get("remaining_m", 0.0)),
		"nav_eta_seconds": float(guidance.get("eta_seconds", INF)),
		"nav_address": str(guidance.get("address", "")),
		"nav_target_point": _nav_target_point(guidance),
		"route_target": routes.target(), "route_recomputes": routes.recomputes,
		"route_points": route_points(), "map_open": map_open(),
		"route_drive_count": int(routes.route().get("drive_points", []).size()),
		"ticket_positions": _ticket_positions(),
		"waypoint_set": routes.has_waypoint(), "waypoint_map": routes.waypoint(),
		"plan_ids": _plan_ids_text(), "unstuck_label": unstuck_label(),
	})
	if dialogue != null:
		values.merge(dialogue.snapshot())
	return Snapshot.new(values)


func get_diagnostics() -> Dictionary:
	return get_snapshot().to_dictionary()
