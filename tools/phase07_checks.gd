extends SceneTree
## Phase 07 acceptance: walk into the generated shop, inspect a real ticket,
## and receive its exact boxes once the bounded prep completes.

const Fixture = preload("res://tools/dev_fixture.gd")
const Layers = preload("res://scripts/collision_layers.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")

const RUN_SETTINGS := "user://phase07-run.cfg"
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
	await process_frame


func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
	await process_frame


func walk(actions: Array[String], count: int) -> void:
	for action in actions:
		Input.action_press(action)
	for _i in range(count):
		await physics_frame
	for action in actions:
		Input.action_release(action)
	await frame()


func create_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	game.get_window().size = Vector2i(1280, 720)
	await frame()
	game.set_order_seed(20261018)
	game.settings.configure(RUN_SETTINGS, true)
	game.settings.load_settings()
	await frame()


func destroy_game() -> void:
	game.settings.reset_to_defaults(false)
	game.queue_free()
	game = null
	await frame()
	await create_timer(0.2).timeout


func yaw_towards(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	return rad_to_deg(atan2(-d.x, -d.z))


func prompt_for(label: String) -> String:
	return "[%s]   %s" % [InputBindings.prompt("interact"), label]


func stand(where: Vector3, yaw := NAN) -> void:
	Fixture.place(game, "pip", where, yaw)
	await frames(2)


func shop_geometry_checks() -> void:
	var shop: Node3D = game.town.get_node("PizzaShop")
	check(game.world.counter_access != null and game.world.staff_station != null
		and game.world.shop_entrance != null and game.world.ready_stock != null,
		"generated shop exports entrance, counter, staff and stock anchors")
	var expected_access: Vector3 = shop.global_transform * Vector3(0, 0, -0.05)
	var expected_entrance: Vector3 = shop.global_transform * Vector3(0, 0, 2.72)
	check(game.world.counter_access.global_position.distance_to(expected_access) < 0.01
		and game.world.shop_entrance.global_position.distance_to(expected_entrance) < 0.01,
		"counter and entrance markers follow the town's rotated shop transform")
	check(game.pickup_point.global_position.distance_to(game.world.counter_access.global_position) < 0.01,
		"legacy PickupPoint now aliases the counter approach instead of the service yard")
	check(game.world.staff_station.global_position.distance_to(game.shopkeeper.global_position) < 0.15
		and (-game.shopkeeper.global_basis.z).dot((game.world.shop_entrance.global_position - game.shopkeeper.global_position).normalized()) > 0.8,
		"Mona stands behind the counter facing the public entrance")
	check(shop.get_node_or_null("Shop_collision") == null
		and shop.get_node_or_null("Front_left_collision") != null
		and shop.get_node_or_null("Front_right_collision") != null
		and shop.get_node_or_null("Front_lintel_collision") != null,
		"the shell is split around a full-height doorway")
	check(shop.get_node_or_null("Counter_collision/Shape") is CollisionShape3D,
		"the service counter blocks Pip from walking through the work area")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, 8.0), Vector3(0, 1.0, 9.5), Layers.WORLD)
	check(game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),
		"the doorway has a clear physics path into the shop")


func preparation_checks() -> void:
	check(game.start_shift(), "a shift creates the first shop ticket")
	check(game.orders.ticket_state == game.orders.TicketState.PREPARING
		and is_zero_approx(game.orders.remaining) and not game.timer_visible,
		"the ticket starts preparing with no food deadline running")
	check(not game.world.ready_stock.visible and not game.orders.pickup()
		and game.orders.cargo_count == 0,
		"unready boxes cannot be collected or appear on the shelf")
	await stand(game.world.counter_access.global_position)
	check(game.presentation.prompt_id == &"shop.counter"
		and game.presentation.prompt_text == prompt_for("CHECK TICKET"),
		"the staffed counter offers a ticket check while preparing")
	game.interact()
	check(game.dialogue.active() and game.dialogue.node_id == "preparing",
		"Mona explains the current ticket is still being prepared")
	var prep_before: float = game.orders.preparation_remaining
	await frames(8)
	check(is_equal_approx(game.orders.preparation_remaining, prep_before)
		and is_zero_approx(game.orders.remaining),
		"opening the transactional conversation freezes prep and freshness time")
	await Fixture.finish_talk(game, 1)
	await frame()
	check(not game.dialogue.active() and game.orders.ticket_state == game.orders.TicketState.PREPARING
		and game.orders.cargo_count == 0 and is_zero_approx(game.orders.remaining),
		"leaving the ticket unchanged does not commit a pickup")
	await frames(90)
	check(game.orders.ticket_state == game.orders.TicketState.READY
		and game.orders.preparation_remaining <= 0.0,
		"the bounded preparation completes while the world is running")
	check(game.world.ready_stock.visible and not game.timer_visible
		and is_zero_approx(game.orders.remaining),
		"ready stock appears at the counter while the freshness clock stays stopped")
	var stock_count := 0
	for box in game.world.ready_stock.get_children():
		if box.visible:
			stock_count += 1
	check(stock_count == game.orders.pizzas,
		"the counter shelf shows exactly the ticket quantity (%d/%d)" % [stock_count, game.orders.pizzas])


func physical_shop_walk() -> void:
	game.restart()
	check(game.start_shift(), "a fresh run starts at the authored player spawn")
	Fixture.place(game, "pip", game.world.player_spawn.global_position)
	game.camera.reduced_motion = true
	game.camera.yaw = deg_to_rad(127.0)
	await frames(3)
	await walk(["move_forward"], 70)
	var front_plane_z: float = game.town.get_node("PizzaShop").to_global(Vector3(0, 0, 2.1)).z
	check(game.pip.global_position.z > front_plane_z + 0.12
		and absf(game.pip.global_position.x) < 0.55,
		"Pip walks from the normal spawn through the open doorway")
	game.camera.yaw = PI
	await frames(3)
	await walk(["move_forward"], 30)
	check(game.pip.global_position.z > game.world.shop_entrance.global_position.z + 1.0,
		"Pip reaches the clear queue area inside the shop")
	game.camera.yaw = PI
	await frames(2)
	await walk(["move_back"], 38)
	check(game.pip.global_position.z < front_plane_z - 0.12
		and absf(game.pip.global_position.y - game.world.player_spawn.global_position.y) < 0.5,
		"Pip walks back outside without clipping or falling")
	game.camera.yaw = PI
	await frames(2)
	await walk(["move_forward"], 38)
	check(game.pip.global_position.z > front_plane_z + 0.12,
		"the same doorway remains passable on re-entry")


func access_and_receipt_checks() -> void:
	var shop: Node3D = game.town.get_node("PizzaShop")
	var back := shop.to_global(Vector3(0, 0.15, -2.55))
	await stand(back, yaw_towards(back, game.world.counter_access.global_position))
	check(game.presentation.prompt_id != &"shop.counter",
		"the back wall and service yard cannot select the counter")
	game.interact()
	check(not game.dialogue.active() and game.orders.cargo_count == 0,
		"interacting from behind the building cannot receive a ticket")
	var van_at_counter: Vector3 = game.world.counter_access.global_position
	Fixture.place(game, "van", van_at_counter, 180.0)
	Fixture.driving(game, true)
	await frames(2)
	check(game.presentation.prompt_id != &"shop.counter",
		"the shop counter is unavailable while Pip is seated in the van")
	Fixture.driving(game, false)
	Fixture.place(game, "van", game.world.van_spawn.global_position)
	var approach := Vector3(0, game.pip.global_position.y, game.world.counter_access.global_position.z - 0.7)
	await stand(approach, yaw_towards(approach, game.world.counter_access.global_position))
	var wall := StaticBody3D.new()
	wall.name = "Phase07ProbeWall"
	wall.collision_layer = Layers.WORLD
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 2.0, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = (game.pip.global_position + game.world.counter_access.global_position) * 0.5 + Vector3(0, 1.0, 0)
	await frames(2)
	check(game.presentation.prompt_id != &"shop.counter",
		"an obstruction between Pip and Mona blocks the interaction")
	wall.queue_free()
	await frame()
	await stand(game.world.counter_access.global_position)
	check(game.presentation.prompt_id == &"shop.counter"
		and game.presentation.prompt_text == prompt_for("TAKE THE ORDER"),
		"a clear approach offers only the ready ticket")
	var address := str(game.order_house.get_meta("address"))
	var customer_name := str(game.order_house.get_meta("label"))
	await frame()
	check(game.hud._ticket_id.text == "ORDER #%02d" % game.active_order_id
		and game.hud._ticket_details.text.contains(address.to_upper())
		and game.hud._ticket_details.text.contains(customer_name.to_upper())
		and game.hud._ticket_status.text == "READY AT THE COUNTER",
		"the ticket card identifies its order, customer, address, quantity and ready state")
	var order_id: int = game.active_order_id
	var pizzas: int = game.order_pizzas
	var receipts: Array[Dictionary] = []
	game.orders.receipt_created.connect(func(event: Dictionary) -> void: receipts.append(event))
	game.interact()
	await Fixture.finish_talk(game, 1)
	await frame()
	check(not game.dialogue.active() and game.active_order_id == order_id
		and game.orders.ticket_state == game.orders.TicketState.READY
		and game.orders.cargo_count == 0,
		"choosing NOT YET leaves the ready ticket unchanged")
	game.interact()
	check(game.dialogue.active() and game.dialogue.node_id == "greet",
		"the same ready ticket remains available after cancellation")
	var greeting: String = game.dialogue.text()
	check(not greeting.contains("{{") and greeting.contains("#%02d" % order_id)
		and greeting.contains(address) and greeting.contains(customer_name),
		"Mona's dialogue reads the real ticket identity and destination")
	await Fixture.finish_talk(game, 0)
	await frame()
	check(game.orders.ticket_state == game.orders.TicketState.COLLECTED
		and game.orders.lifecycle == game.orders.Lifecycle.ON_ROUTE
		and game.orders.cargo_count == pizzas and game.pip.carrying == pizzas,
		"the confirmed handoff transfers exactly the assigned boxes")
	check(receipts.size() == 1 and receipts[0].order_id == order_id
		and receipts[0].quantity == pizzas and receipts[0].ticket_state == "collected",
		"the receipt signal publishes one immutable, quantity-bearing handoff event")
	check(game.world.ready_stock.visible == false and game.timer_visible
		and absf(game.orders.remaining - game.orders.duration) < 0.2,
		"freshness starts at receipt as shelf stock disappears")
	check(game.presentation.prompt_id == &"shop.counter"
		and game.presentation.prompt_text == "HANDS FULL"
		and not game.orders.pickup() and receipts.size() == 1,
		"repeat interaction and direct duplicate pickup cannot mint another receipt")
	check(game.hud._ticket_status.text.begins_with("COLLECTED"),
		"the ticket stays visible as collected during delivery")


func restart_during_prep_checks() -> void:
	game.restart()
	check(game.orders.ticket_state == game.orders.TicketState.NONE
		and not game.world.ready_stock.visible and game.orders.cargo_count == 0,
		"restart clears preparation and stale shelf stock")
	check(game.start_shift() and game.orders.ticket_state == game.orders.TicketState.PREPARING,
		"the next shift creates a new preparing ticket")
	await stand(game.world.counter_access.global_position)
	game.interact()
	check(game.dialogue.active() and game.dialogue.node_id == "preparing",
		"the new ticket owns its own preparation conversation")
	var old_generation: int = game.session.generation
	game.restart()
	await frame()
	check(not game.dialogue.active() and game.session.generation > old_generation
		and game.orders.ticket_state == game.orders.TicketState.NONE
		and game.orders.cargo_count == 0 and not game.world.ready_stock.visible,
		"restart during dialogue invalidates the old ticket without a late handoff")


func run() -> void:
	await create_game()
	if not game.world_ready:
		check(false, "world binds before Phase 07 checks")
	else:
		await shop_geometry_checks()
		await preparation_checks()
		await physical_shop_walk()
		await access_and_receipt_checks()
		await restart_during_prep_checks()
	await destroy_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SETTINGS))
	print("PHASE 07: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
