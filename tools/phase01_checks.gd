extends SceneTree
## Focused phase-01 acceptance checks, not the phase-02 scenario runner.
## godot --headless --audio-driver Dummy --path . --script tools/phase01_checks.gd

const Fixture = preload("res://tools/dev_fixture.gd")

var failures := 0
var checks := 0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func key(code: Key) -> void:
	var event := InputEventKey.new()
	# Real keyboards report both the logical and the physical key. Menus use the
	# builtin ui_accept/ui_down actions, which match on the logical keycode, while
	# gameplay actions match the physical one, so synthetic input sets both.
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	# 4.7 names device ids (keyboard=16, mouse=32); earlier builds default to 0.
	# Negative ids are emulation, which ordinary synthetic input must not use.
	check(event.device >= 0, "input uses ordinary keyboard device")
	root.push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	root.push_input(event)

func frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	# physics_frame is emitted before the actor tick; observe after that tick.
	await process_frame

func box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.global_position = pos
	return body

func start() -> void:
	game.restart()
	game.force_destination_index(0)
	game._start_shift()
	await frames()

func ensure_ticket_ready() -> void:
	if game.orders.lifecycle == game.orders.Lifecycle.AT_SHOP \
			and game.orders.ticket_state == game.orders.TicketState.PREPARING:
		game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())

func receive_ticket() -> void:
	await ensure_ticket_ready()
	game.orders.pickup()

func seat_at(pos: Vector3, yaw: float = 0.0) -> void:
	await start()
	game.van.global_position = pos
	game.van.rotation = Vector3(0, yaw, 0)
	game.van.velocity = Vector3.ZERO
	game.van.speed = 0.0
	game.pip.global_position = pos + Vector3(2, 0.1, 0)
	check(game._enter_van(), "enter stopped van in range")
	await frames()

func run() -> void:
	InputMap.load_from_project_settings()
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	check(game.world_ready and game.houses.size() == 8, "valid world and eight houses")
	check(not game.pip.input_enabled and not game.van.input_enabled, "title has no movement owner")
	key(KEY_ENTER)
	await frames()
	check(game.state == game.State.TO_SHOP, "real Enter input starts shift")
	check(game.pip.input_enabled and not game.van.input_enabled, "on foot owns movement exclusively")
	var first_order: Node3D = game.order_house
	Fixture.money(game, 12)
	game._start_shift()
	check(game.money == 12 and game.order_house == first_order, "duplicate start cannot reset active shift")
	for cycle in range(3):
		key(KEY_ESCAPE)
		check(paused and game.paused, "Esc pauses cycle %d" % cycle)
		check(not game.can_process() and game.get_node("SessionInput").can_process(), "only session input/HUD remain responsive")
		check(not game.pip.input_enabled and not game.van.input_enabled, "paused movement has no owner")
		var timer: float = game.timer
		var p: Vector3 = game.pip.global_position
		var v: Vector3 = game.van.global_position
		Input.action_press("move_forward")
		game._on_interact()
		await frames(8)
		Input.action_release("move_forward")
		check(game.timer == timer and game.pip.global_position == p and game.van.global_position == v, "pause freezes clocks and both actors")
		key(KEY_ESCAPE)
		check(not paused and not game.paused and game.pip.input_enabled, "Esc resumes cycle %d" % cycle)
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		await start()
		var p: Vector3 = game.pip.global_position
		var v: Vector3 = game.van.global_position
		Input.action_press(action)
		await frames(15)
		Input.action_release(action)
		var flat_delta: Vector3 = game.van.global_position - v
		flat_delta.y = 0
		check(flat_delta.length() < 0.001 and game.van.speed == 0, action + " leaves parked van stationary")
		check(game.pip.global_position.distance_to(p) > 0.1, action + " moves Pip")
	for i in range(2):
		game.orders.reset(game.session.generation + i)
		game.force_destination_index(0)
		game._new_order()
		check(game.last_house == 0, "forced repeated house 0 takes precedence for a fresh job board")
	for i in range(20):
		var previous: String = game.orders.destination_id
		var current: int = game.orders.order_id
		game.orders.tick(game.orders.preparation_remaining + 0.05, game.destination_ids())
		var received: bool = game.orders.pickup_order(current)
		var delivered: bool = game.orders.settle_order(game.destination_ids(), game.orders.generation, current, previous) if received else false
		game.orders.money = 0
		game.orders.deliveries = 0
		check(received and delivered and game.orders.destination_id != previous,
			"random orders deliver and avoid an immediate customer repeat")
	var saved_houses = game.houses.duplicate()
	game.houses.assign([saved_houses[0]])
	Fixture.last_house(game, 0)
	game._new_order()
	check(game.last_house == 0, "single house does not loop")
	game.houses.assign(saved_houses)
	await seat_at(Vector3(0, 0.1, 2))
	var hidden_pip: Vector3 = game.pip.global_position
	Input.action_press("move_forward")
	await frames(12)
	Input.action_release("move_forward")
	check(game.van.speed > 0.5 and game.pip.global_position == hidden_pip and not game.pip.visible,
		"driving moves only van, hidden Pip stays still")
	var speed: float = game.van.speed
	check(not game._exit_van() and game.driving and game.van.speed == speed, "fast exit rejected without braking")
	Fixture.paused(game, true)
	check(not game._exit_van(), "paused exit rejected")
	Fixture.paused(game, false)
	Fixture.driving(game, false)
	game.pip.global_position = game.van.global_position
	check(not game._enter_van() and not game.driving, "fast entry rejected")
	Fixture.driving(game, true)
	game._sync_movement()
	Input.action_press("handbrake")
	await frames(30)
	Input.action_release("handbrake")
	check(game._van_stopped(), "actual handbrake controls stop the van")
	key(KEY_E)
	check(not game.driving and game.pip.visible, "E exits safely after braking to a stop")
	await start()
	await receive_ticket()
	Fixture.timer(game, game.timer_max * 0.25)
	game._context()
	check(game.target_sub == "TIP  $2", "delivery tip display follows remaining time")
	game.pip.global_position = game.van.global_position + Vector3(2, 0, 0)
	game.van.speed = 0
	game.van.velocity = Vector3.ZERO
	game._enter_van()
	Fixture.timer(game, 0)
	game._context()
	check(game.target_sub == "TIP  $0", "driving tip keeps updating")
	await collision_checks()
	await settlement_and_reset_checks()
	await world_checks()
	game.queue_free()
	await frames()
	# Dummy audio releases stopped playback on the mix thread, in wall time.
	# A headless fixture can otherwise quit before that cleanup runs.
	await create_timer(0.15).timeout
	print("PHASE 01: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func collision_checks() -> void:
	# An isolated floor makes support/clearance tests independent of town props.
	var floor_body := box(Vector3(150, -0.5, 0), Vector3(20, 1, 20))
	await seat_at(Vector3(150, 0.1, 0))
	check(game.van.get_node("Visual/Van_collision").collision_layer == 0,
		"visual static collider disabled; moving van owns collision")
	check(game._exit_van() and game.pip.global_position.x > 151,
		"clear positive-X side exit passes capsule and support probes")
	await seat_at(Vector3(150, 0.1, 0))
	var thin_wall := box(Vector3(151.10, 1.5, 0), Vector3(0.05, 3, 4))
	await frames()
	check(game._exit_van() and game.pip.global_position.x < 149,
		"capsule sweep rejects a thin wall before a clear endpoint")
	thin_wall.queue_free()
	await frames()
	await seat_at(Vector3(150, 0.1, 0))
	var side_wall := box(Vector3(151.6, 1.5, 0), Vector3(0.3, 3, 6))
	await frames()
	check(game._exit_van() and game.pip.global_position.x < 149,
		"blocked first side falls back to clear opposite side")
	var other_wall := box(Vector3(148.4, 1.5, 0), Vector3(0.3, 3, 6))
	await seat_at(Vector3(150, 0.1, 0))
	check(game._exit_van() and game.pip.global_position.z < -2,
		"blocked sides fall back to clear rear")
	var rear_wall := box(Vector3(150, 1.5, -2.6), Vector3(4, 3, 0.3))
	await seat_at(Vector3(150, 0.1, 0))
	var pip_before: Vector3 = game.pip.global_position
	check(not game._exit_van() and game.driving and not game.pip.visible
		and game.pip.global_position == pip_before, "fully blocked exit preserves seated state")
	for wall in [side_wall, other_wall, rear_wall]:
		wall.queue_free()
	await frames()
	await seat_at(Vector3(150, 0.1, 0), PI / 2)
	check(game._exit_van() and game.pip.global_position.z < -1,
		"exit offsets follow rotated van world transform")
	# A low beam above Pip's head ray catches center-only clearance checks.
	var ceiling := box(Vector3(150, 1.5, 0), Vector3(8, 0.25, 8))
	await seat_at(Vector3(150, 0.1, 0))
	check(not game._exit_van() and game.driving, "low ceiling blocks actual capsule")
	ceiling.queue_free()
	floor_body.queue_free()
	await frames()
	# A center ray alone would accept this tiny ledge. The capsule footprint
	# needs support beyond that ray; other candidates have no floor at all.
	var ledge := box(Vector3(151.54, -0.1, 0.15), Vector3(0.15, 0.2, 0.15))
	await seat_at(Vector3(150, 0.1, 0))
	game.van.set_physics_process(false)
	game.van.velocity = Vector3.ZERO
	game.van.speed = 0
	var ray := PhysicsRayQueryParameters3D.create(Vector3(151.54, 0.5, 0.15), Vector3(151.54, -0.5, 0.15), 1)
	check(not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "ledge fixture supports center ray")
	check(not game._exit_van(), "partial footprint on a ledge is not a safe exit")
	ledge.queue_free()
	var ramp := box(Vector3(151.54, -0.1, 0.15), Vector3(1.0, 0.2, 8))
	ramp.rotation.z = deg_to_rad(60)
	await frames()
	var ramp_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not ramp_hit.is_empty() and ramp_hit.normal.dot(Vector3.UP) < cos(game.pip.floor_max_angle), "ramp fixture exceeds Pip's floor angle")
	check(not game._exit_van(), "steep support rejects exit")
	ramp.queue_free()
	await frames()
	# No world floor under this isolated location. The vehicle roof must not
	# count as support, and the capsule may not be teleported into empty space.
	await seat_at(Vector3(150, 0.1, 0))
	game.van.set_physics_process(false)
	game.van.speed = 0
	game.van.velocity = Vector3.ZERO
	check(not game._exit_van() and game.driving, "unsupported exits rejected, van roof excluded")
	floor_body = box(Vector3(150, -0.5, 0), Vector3(20, 1, 20))
	for direction in [1.0, -1.0]:
		await seat_at(Vector3(150, 0.1, 0))
		var wall := box(Vector3(150, 1.5, direction * 2.25), Vector3(8, 3, 0.5))
		game.van.speed = direction * 4
		await frames(6)
		check(absf(game.van.speed) < 1.0, "signed contact response direction=%s" % direction)
		wall.queue_free()
		await frames()
	# A plain character on WORLD is a real contact without the apply_push API.
	await seat_at(Vector3(150, 0.1, 0))
	var character := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 3, 0.5)
	collision.shape = shape
	character.add_child(collision)
	game.add_child(character)
	character.global_position = Vector3(150, 1.5, 2.25)
	game.van.speed = 4
	await frames(6)
	check(absf(game.van.speed) < 1, "plain CharacterBody3D contact does not dispatch apply_push")
	character.queue_free()
	floor_body.queue_free()
	await frames()

func settlement_and_reset_checks() -> void:
	await start()
	await ensure_ticket_ready()
	game.pip.global_position = game.pickup_point.global_position
	key(KEY_E)
	# The press now opens the counter conversation: the pickup is its committed end.
	await Fixture.finish_talk(game)
	check(game.state == game.State.TO_HOUSE and game.pip.carrying == game.order_pizzas,
		"real E input picks up current order")
	game.pip.global_position = game.order_house.get_node("Door").global_position
	# The door conversation belongs to the phase 06 checks; settlement is this one's.
	game._deliver()
	check(game.deliveries == 1 and game.money > 0 and game.pip.carrying == 0, "delivery pays and clears cargo")
	var paid: int = game.money
	game._deliver()
	check(game.deliveries == 1 and game.money == paid, "duplicate delivery does not pay again")
	await receive_ticket()
	Fixture.timer(game, 0)
	game._on_timeout()
	game._on_timeout()
	check(game.strikes == 1, "same timeout cannot strike new order twice")
	game.pip.autopilot = Vector3(20, 0, 0)
	game.van.autopilot = Vector3(-20, 0, 0)
	game.van.speed = 4
	game.pip.velocity = Vector3(4, 0, 0)
	game._finish(true)
	check(game.pip.autopilot == Vector3.INF and game.van.autopilot == Vector3.INF
		and game.pip.velocity == Vector3.ZERO and game.van.velocity == Vector3.ZERO
		and game.van.speed == 0, "finish cancels both controllers and all actor momentum")
	var p: Vector3 = game.pip.global_position
	var v: Vector3 = game.van.global_position
	var timer: float = game.timer
	game._on_interact()
	game._on_timeout()
	game._new_order()
	# Even newly injected dev hooks cannot bypass terminal ownership.
	game.pip.autopilot = Vector3(20, 0, 0)
	game.van.autopilot = Vector3(-20, 0, 0)
	await frames(8)
	check(game.pip.global_position == p and game.van.global_position == v
		and game.timer == timer and game.money == paid, "terminal state freezes actors, orders, and payment")
	check(not game.pip.input_enabled and not game.van.input_enabled, "result has no movement owner")
	key(KEY_R)
	check(game.state == game.State.TITLE and game.money == 0 and game.timer == 0
		and game.pip.autopilot == Vector3.INF and game.van.autopilot == Vector3.INF,
		"result restart resets session and dev controllers")
	for i in range(3):
		await seat_at(Vector3(0, 0.1, 2))
		key(KEY_ESCAPE)
		key(KEY_R)
		await frames()
		check(not paused and not game.paused and not game.driving and game.pip.visible
			and not game.pip.get_node("Collision").disabled and game.state == game.State.TITLE,
			"paused seated restart restores player and title cycle %d" % i)
		check(game.pip.velocity == Vector3.ZERO and game.van.speed == 0
			and game.camera.target == game.pip and not game.camera.driving and game.camera.orbit
			and not game.pickup_marker.visible and not game.deliver_marker.visible
			and game.prompt_text.is_empty(), "restart clears motion, camera, markers and prompt")
	key(KEY_R)
	check(game.state == game.State.TITLE and game.money == 0, "restart from title is safe")
	await start()
	for i in range(3):
		await receive_ticket()
		Fixture.timer(game, 0)
		game._on_timeout()
	check(game.state == game.State.FAILED and game.strikes == 3, "three distinct timeouts end shift")
	key(KEY_R)
	check(game.state == game.State.TITLE and game.strikes == 0, "failed result restart resets strikes")

func world_checks() -> void:
	# Validate contract diagnostics on an isolated instance; never modify town
	# resources or the active fixture's world references.
	for path in ["Town/Houses", "Town/PlayerSpawn", "Town/VanSpawn", "Town/PizzaShop/PickupPoint", "Town/Houses/House_02/Door"]:
		var broken = load("res://scenes/game.tscn").instantiate()
		var node = broken.get_node_or_null(path)
		if node == null:
			# House node names are authoring details; use the first actual house.
			node = broken.get_node("Town/Houses").get_child(0).get_node("Door")
		node.get_parent().remove_child(node)
		node.free()
		root.add_child(broken)
		check(not broken.world_ready and not broken.world_errors.is_empty(), "invalid world rejected: " + path)
		broken._start_shift()
		check(broken.state == broken.State.FAILED, "invalid world cannot start")
		broken.queue_free()
		await frames()
