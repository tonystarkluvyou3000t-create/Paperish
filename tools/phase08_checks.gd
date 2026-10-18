extends SceneTree
## Phase 08 lifecycle checks. These use service fixtures for exact transaction
## boundaries; Phase 06/07 retain the real-input interaction and shop route tests.

const Fixture = preload("res://tools/dev_fixture.gd")

var failures := 0
var checks := 0


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


func make_game(seed: int) -> Node:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	game.set_order_seed(seed)
	game.start_shift()
	await frame()
	return game


func drop_game(game: Node) -> void:
	Fixture.cleanup(game)
	game.queue_free()
	await frame()
	await create_timer(0.1).timeout


func prepare(game: Node, order: int = -1) -> void:
	var id: int = game.orders.order_id if order < 0 else order
	var data: Dictionary = game.orders.order_data(id)
	if str(data.get("ticket_state_name", "")) == "preparing":
		game.orders.tick(float(data.preparation_remaining) + 0.05, game.destination_ids())
	await frame()


func run() -> void:
	await single_order_transaction()
	await queued_batch_and_capacity()
	await expiry_reclassifies_cargo()
	print("PHASE 08: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func single_order_transaction() -> void:
	var game := await make_game(20261018)
	var order: int = game.orders.order_id
	var generation: int = game.orders.generation
	var quantity: int = game.orders.pizzas
	var destination: String = game.orders.destination_id
	var receipts: Array[Dictionary] = []
	var settlements: Array[Dictionary] = []
	game.orders.receipt_created.connect(func(value: Dictionary) -> void: receipts.append(value))
	game.orders.settled.connect(func(value: Dictionary) -> void: settlements.append(value))
	check(quantity >= 1 and quantity <= game.cargo.player_capacity,
		"default ticket quantity fits Pip's carry capacity")
	check(game.cargo.package_ids(order).size() == quantity
		and game.cargo.location_for_order(order) == "counter",
		"receipt preparation creates one stable counter package per pizza")
	var package_ids: Array[String] = game.cargo.package_ids(order)
	check(package_ids.size() == package_ids.duplicate().size()
		and package_ids[0].begins_with("g%03d-o%03d" % [generation, order]),
		"package IDs encode generation and order identity")
	check(game.cargo.invariant_errors().is_empty(), "initial counter cargo satisfies location invariants")
	check(not game.orders.settle_order(game.destination_ids(), generation, order, "wrong address"),
		"a wrong address cannot settle the ticket")
	await prepare(game, order)
	check(game.orders.can_pickup(order) and game.cargo.location_for_order(order) == "counter",
		"the ready ticket can be accepted only while its bundle is at the counter")
	check(game.orders.pickup_order(order), "the staff receipt transfers the entire bundle to Pip")
	check(game.cargo.location_for_order(order) == "pip" and game.pip.carrying == quantity
		and receipts.size() == 1 and receipts[0].is_read_only(),
		"one immutable receipt owns every held package")
	check(not game.orders.pickup_order(order) and receipts.size() == 1,
		"duplicate receipt input cannot create or transfer a second bundle")
	check(game.cargo.transfer_order(order, "pip", "van"), "the van cargo door accepts the held order bundle")
	check(game.cargo.location_for_order(order) == "van" and game.pip.carrying == 0
		and game.cargo.count_at("van") == quantity,
		"loading moves each package once and clears Pip's visible stack")
	check(not game.orders.settle_order(game.destination_ids(), generation, order, destination),
		"cargo still in the van cannot be delivered from the doorstep")
	check(game.cargo.transfer_order(order, "van", "pip"), "Pip retrieves the selected order from the van")
	check(game.cargo.location_for_order(order) == "pip" and game.pip.carrying == quantity,
		"unloading restores the bundle to Pip without changing package IDs")
	var actor: Node3D = game._customer_actors[order]
	check(game._talk_customer(order, actor), "the matching customer opens the receiving conversation")
	await Fixture.finish_talk(game)
	await frame()
	check(settlements.size() == 1 and settlements[0].order_id == order,
		"the customer handoff emits exactly one settlement for this order")
	var event: Dictionary = settlements[0]
	check(event.pay == event.base_pay + event.pizza_pay + event.tip_pay + event.quality_adjustment
		and event.settlement_total == event.pay,
		"the immutable settlement itemizes base, pizzas, tip and quality")
	check(not game.orders.settle_order(game.destination_ids(), generation, order, destination)
		and settlements.size() == 1,
		"a repeated handoff pays exactly once")
	check(game.cargo.location_for_order(order) == "customer"
		and game.cargo.count_for_order(order, ["customer"]) == quantity,
		"settled packages are reclassified at the customer and never remain deliverable")
	check(game.cargo.invariant_errors().is_empty(), "settlement preserves the global cargo invariant")
	await drop_game(game)


func queued_batch_and_capacity() -> void:
	var game := await make_game(3408)
	var first: int = game.orders.order_id
	var first_destination: String = game.orders.destination_id
	await prepare(game, first)
	check(game.orders.pickup_order(first), "the first batch ticket is received")
	var ids: Array[String] = game.destination_ids()
	var alternate := ""
	for id in ids:
		if id != first_destination:
			alternate = id
			break
	check(not alternate.is_empty() and game.orders.force_destination(alternate, ids),
		"the queued ticket can target a different customer")
	check(game.orders.queue_ticket(ids, false), "Mona can queue a second feasible delivery")
	var second := 0
	for id in game.orders.outstanding_order_ids():
		if id != first:
			second = id
	check(second > first and game.orders.destination_for_order(second) == alternate,
		"queued tickets keep stable unique IDs and destinations")
	var total: int = game.cargo.package_ids(first).size() + game.cargo.package_ids(second).size()
	check(game.orders.order_count() == 2 and total <= game.cargo.van_capacity,
		"the job board and van capacity accept only the combined bundle size")
	await prepare(game, second)
	var first_quantity: int = game.cargo.package_ids(first).size()
	var second_quantity: int = game.cargo.package_ids(second).size()
	check(game.cargo.transfer_order(first, "pip", "van"), "the first bundle loads into a van slot")
	check(game.orders.pickup_order(second), "a ready queued ticket can be received after loading the first")
	check(game.cargo.transfer_order(second, "pip", "van"), "the second bundle loads into its own van slots")
	check(game.cargo.count_at("van") == total and game.cargo.van_order_ids().size() == 2,
		"two physical bundles coexist in the van without losing their order IDs")
	var full_order := 99
	var extra_order := 100
	var remaining_slots: int = game.cargo.van_capacity - game.cargo.count_at("van")
	var filled_ok := true
	if remaining_slots > 0:
		filled_ok = game.cargo.create_order(game.orders.generation, full_order, "capacity fixture", remaining_slots) \
			and game.cargo.transfer_order(full_order, "counter", "van")
	check(filled_ok and game.cargo.count_at("van") == game.cargo.van_capacity,
		"a completely occupied van is represented with explicit package slots")
	check(game.cargo.create_order(game.orders.generation, extra_order, "extra fixture", 1)
		and game.cargo.transfer_order(extra_order, "counter", "pip"),
		"a separate held bundle can wait beside a full van")
	check(not game.cargo.transfer_order(extra_order, "pip", "van")
		and game.cargo.location_for_order(extra_order) == "pip",
		"a full van rejects another load atomically and keeps the order in Pip's hands")
	check(game.cargo.invariant_errors().is_empty(), "full-slot rejection leaves package and slot invariants valid")
	game.cargo.discard_order(extra_order)
	if remaining_slots > 0:
		check(game.cargo.discard_order(full_order), "the isolated capacity fixture can be discarded")
	else:
		check(true, "the two real bundles already occupy every van slot")
	check(game.cargo.transfer_order(second, "van", "pip"), "Pip can retrieve the selected second bundle")
	var settlements: Array[int] = []
	game.orders.settled.connect(func(value: Dictionary) -> void: settlements.append(int(value.order_id)))
	check(game.orders.settle_order(ids, game.orders.generation, second, alternate),
		"the second batch order may be delivered before the first")
	check(game.cargo.location_for_order(first) == "van" and game.cargo.location_for_order(second) == "customer",
		"out-of-order delivery changes only the matching package bundle")
	check(game.cargo.transfer_order(first, "van", "pip"), "the remaining first order can be retrieved")
	check(game.orders.settle_order(ids, game.orders.generation, first, first_destination),
		"the first batch order settles independently")
	check(settlements == [second, first], "batch settlement events follow actual delivery order")
	check(game.cargo.count_at("van") == 0 and game.cargo.invariant_errors().is_empty(),
		"all delivered and discarded packages leave no occupied van slots")
	check(first_quantity + second_quantity == total, "the batch slot count matches the authored quantities")
	await drop_game(game)


func expiry_reclassifies_cargo() -> void:
	var game := await make_game(8008)
	var first: int = game.orders.order_id
	await prepare(game, first)
	check(game.orders.pickup_order(first), "expiry fixture begins with a normal staff receipt")
	var first_quantity: int = game.cargo.package_ids(first).size()
	game.orders.remaining = 0.0
	check(game.orders.expire_order(game.destination_ids(), game.orders.generation, first),
		"an expired order commits once while Pip carries it")
	check(game.cargo.location_for_order(first) == "discarded" and game.cargo.count_at("pip") == 0
		and game.orders.strikes == 1,
		"carried expired boxes are visibly discarded and count as one order strike")
	check(not game.orders.expire_order(game.destination_ids(), game.orders.generation, first),
		"the same timeout cannot create a duplicate strike")
	var second: int = game.orders.order_id
	await prepare(game, second)
	check(game.orders.pickup_order(second) and game.cargo.transfer_order(second, "pip", "van"),
		"replacement ticket can be received and loaded after a timeout")
	var second_quantity: int = game.cargo.package_ids(second).size()
	game.orders.remaining = 0.0
	check(game.orders.expire_order(game.destination_ids(), game.orders.generation, second),
		"an expired order commits while its boxes are loaded in the van")
	check(game.cargo.location_for_order(second) == "discarded" and game.cargo.count_at("van") == 0
		and game.orders.strikes == 2,
		"van cargo expires to discarded location and frees every slot")
	check(game.cargo.count_for_order(first, ["discarded"]) == first_quantity
		and game.cargo.count_for_order(second, ["discarded"]) == second_quantity
		and game.cargo.invariant_errors().is_empty(),
		"expired package IDs remain auditable with no stale deliverable cargo")
	game.restart()
	check(game.cargo.packages.is_empty() and game.cargo.bundles.is_empty()
		and game.cargo.invariant_errors().is_empty(),
		"a restart clears the old run's package ledger safely")
	await drop_game(game)
