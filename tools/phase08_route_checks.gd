extends SceneTree
## Phase 08 end-to-end acceptance using ordinary movement and vehicle inputs.
## No Fixture.place, actor autopilot, capture-plan navigation, or position writes.

const Fixture = preload("res://tools/dev_fixture.gd")

var failures := 0
var checks := 0
var game: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func frame() -> void:
	await physics_frame
	await process_frame


func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
	await process_frame


func walk_toward(target: Vector3, tolerance := 0.72, max_batches := 180) -> void:
	var previous: Vector3 = game.pip.global_position
	var stalled := 0
	for _batch in range(max_batches):
		var delta: Vector3 = target - game.pip.global_position
		delta.y = 0.0
		if delta.length() <= tolerance:
			break
		game.camera.yaw = atan2(-delta.x, -delta.z)
		Input.action_press("move_forward")
		for _step in range(8):
			await physics_frame
		Input.action_release("move_forward")
		await process_frame
		if game.pip.global_position.distance_to(previous) < 0.035:
			stalled += 1
		else:
			stalled = 0
		previous = game.pip.global_position
		if stalled >= 8:
			break
	await frame()
	print("FOOT target=", target, " actual=", game.pip.global_position,
		" distance=", game.pip.global_position.distance_to(target))


func drive(actions: Array[String], count: int) -> void:
	for action in actions:
		Input.action_press(action)
	await frames(count)
	for action in actions:
		Input.action_release(action)
	await frames(2)


func run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(3)
	game.set_order_seed(20261018)
	game.camera.reduced_motion = true
	check(game.orders.force_destination("6 Marinara Way", game.destination_ids()),
		"a nearby east-district address is selected for the physical route")
	check(game.start_shift(), "the normal shift starts from the authored player and van spawns")
	await frames(90)
	var counter_approach := Vector3(0.0, game.pip.global_position.y, 8.5)
	await walk_toward(counter_approach)
	await walk_toward(game.world.counter_access.global_position, 0.55)
	print("COUNTER prompt=", game.presentation.prompt_id, " access=", game.world.counter_access.global_position)
	check(game.pip.global_position.distance_to(game.world.counter_access.global_position) < 1.3,
		"Pip walks through the shop doorway to Mona")
	check(game.orders.ticket_state == game.orders.TicketState.READY,
		"the ticket is ready at the staffed counter")
	check(game.presentation.prompt_id == &"shop.counter", "the staffed counter accepts interaction")
	game.interact()
	if game.dialogue.active():
		await Fixture.finish_talk(game, 0)
	await frame()
	var order: int = game.orders.order_id
	check(game.orders.lifecycle_name(order) == "on_route" and game.cargo.location_for_order(order) == "pip",
		"Mona's conversation hands the exact ticket to Pip")

	# Go around the west/rear side of the van, load, then circle around its front
	# to the driver door. All actor movement comes from move_forward inputs.
	await walk_toward(Vector3(0.0, game.pip.global_position.y, 8.25))
	await walk_toward(Vector3(-2.65, game.pip.global_position.y, 4.1))
	await walk_toward(Vector3(-2.65, game.pip.global_position.y, 1.85))
	check(game.presentation.prompt_id == &"van.cargo.load",
		"the rear cargo door offers the held bundle")
	game.interact()
	await frame()
	check(game.cargo.location_for_order(order) == "van" and game.pip.carrying == 0,
		"E transfers all packages into van slots")
	await walk_toward(Vector3(-2.65, game.pip.global_position.y, 0.0))
	await walk_toward(Vector3(2.35, game.pip.global_position.y, 0.0))
	await walk_toward(Vector3(1.2, game.pip.global_position.y, 0.2))
	check(game.presentation.prompt_id == &"van.driver",
		"the driver door remains reachable with cargo aboard")
	game.interact()
	await frame()
	check(game.driving and not game.pip.visible, "the driver interaction seats Pip safely")
	var start_position: Vector3 = game.van.global_position
	await drive(["move_forward"], 88)
	check(game.van.global_position.distance_to(start_position) > 8.0,
		"ordinary throttle input moves the van along Marinara Way")
	print("DRIVE straight=", game.van.global_position, " yaw=", game.van.rotation.y,
		" speed=", game.van.speed)
	await drive(["move_back"], 28)
	await drive(["move_forward", "move_left"], 48)
	print("DRIVE turn=", game.van.global_position, " yaw=", game.van.rotation.y,
		" speed=", game.van.speed)
	await drive(["move_forward"], 24)
	await drive(["handbrake"], 30)
	await frames(10)
	var park: Node3D = game.world.destination("6 Marinara Way").get_node("Park")
	print("DRIVE stop=", game.van.global_position, " yaw=", game.van.rotation.y,
		" speed=", game.van.speed, " park=", park.global_position)
	check(absf(game.van.speed) <= game.balance.stopped_speed,
		"brake input stops the van before Pip exits")
	var stopped_position: Vector3 = game.van.global_position
	check(game.presentation.prompt_id == &"van.seat", "the stopped van offers a safe exit")
	game.interact()
	await frames(2)
	check(game.pip.visible and game.pip.collision_layer != 0
		and game.van.global_position.distance_to(stopped_position) < 0.1,
		"safe exit restores Pip on foot without moving the van")

	var actor: Node3D = game._customer_actors[order]
	var rear_waypoint := Vector3(game.van.global_position.x + 2.7,
		game.pip.global_position.y, game.van.global_position.z + 2.7)
	await walk_toward(rear_waypoint)
	var cargo_access: Vector3 = game.van.global_transform * Vector3(0.0, 0.0, -2.45)
	await walk_toward(cargo_access)
	check(game.presentation.prompt_id == &"van.cargo.unload",
		"Pip reaches the rear hatch to retrieve the selected delivery")
	game.interact()
	await frame()
	check(game.cargo.location_for_order(order) == "pip" and game.pip.carrying > 0,
		"the matching bundle unloads back into Pip's hands")
	var customer_access: Vector3 = actor.global_transform * Vector3(0.0, 0.0, -0.75)
	await walk_toward(customer_access, 1.5)
	check(game.presentation.prompt_id == StringName("house.customer"),
		"the correct customer's door offers the order")
	game.interact()
	check(game.dialogue.active(), "the customer dialogue opens at the correct address")
	if game.dialogue.active():
		await Fixture.finish_talk(game, 0)
	await frame()
	check(game.orders.deliveries == 1 and game.orders.money > 0
		and game.cargo.location_for_order(order) == "customer",
		"the customer accepts the pizza and the itemized payment settles once")
	check(game.cargo.invariant_errors().is_empty(), "the complete physical route preserves cargo invariants")
	print("PHASE 08 ROUTE: order=", order, " address=6 Marinara Way", " pip=", game.pip.global_position,
		" van=", game.van.global_position)
	Fixture.cleanup(game)
	game.queue_free()
	await frame()
	await create_timer(0.1).timeout
	print("PHASE 08 ROUTE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
