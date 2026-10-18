extends SceneTree
## Cross-service invariants: public commands/snapshots plus isolated setup hooks.
const Fixture = preload("res://tools/dev_fixture.gd")
const Snapshot = preload("res://scripts/services/game_snapshot.gd")
var failures := 0
var checks := 0
var game: Node
var settlements: Array[Dictionary] = []
var settlement_observations: Array[bool] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frame() -> void:
	await physics_frame
	await process_frame
	# process_frame is emitted before HUD._process; observe the completed draw model.
	await process_frame

func create_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	game.set_order_seed(20261018)

func destroy_game() -> void:
	game.queue_free()
	game = null
	await frame()
	await create_timer(0.15).timeout

func observe_settlement(event: Dictionary) -> void:
	settlements.append(event)
	settlement_observations.append(event.is_read_only() and game.orders.money == event.money
		and game.orders.cargo_count == 0 and game.orders.lifecycle == game.orders.Lifecycle.CLOSED)
	# Reentrant and conflicting settlement/timeout requests must both reject.
	settlement_observations.append(not game.orders.settle(game.world.ids(), event.generation, event.order_id))
	settlement_observations.append(not game.orders.expire(game.world.ids(), event.generation, event.order_id))

func deliver() -> void:
	Fixture.place(game, "pip", game.pickup_point.global_position)
	game.interact()
	await frame()
	var view: Snapshot = game.get_snapshot()
	check(view.order_lifecycle == "on_route" and view.cargo_count == game.pip.carrying, "cargo has one authority and player reads it")
	check(view.target_label == str(game.order_house.get_meta("label")).to_upper()
		and game.deliver_marker.global_position == game.order_house.get_node("Door").global_position,
		"snapshot, HUD target and marker share current order")
	Fixture.place(game, "pip", game.order_house.get_node("Door").global_position)
	game.interact()
	await frame()

func run() -> void:
	InputMap.load_from_project_settings()
	await create_game()
	game.force_destination("2 Marinara Way")
	check(game.start_shift(), "public start command begins valid shift")
	check(not game.start_shift(), "duplicate public start rejected")
	var initial: Snapshot = game.get_snapshot()
	check(initial.is_read_only() and initial.session_mode == "playing" and initial.actor_mode == "foot"
		and initial.order_lifecycle == "at_shop", "typed snapshot separates flow, actor and order state")
	var copied := initial.to_dictionary()
	copied.money = 9999
	check(initial.money == 0 and game.get_snapshot().money == 0, "snapshot copy cannot award money")
	check(not game.hud.get("snapshot_provider").is_null(), "HUD receives read-only snapshot supplier")
	check(game.open_modal(&"map") and game.open_modal(&"dialogue"), "two modal owners can pause together")
	var frozen: Snapshot = game.get_snapshot()
	await frame()
	check(paused and game.paused and frozen.session_mode == "paused", "nested modals pause tree and diagnostics")
	check(game.close_modal(&"map") and paused and game.paused, "closing map cannot resume underneath dialogue")
	check(not game.close_modal(&"unknown") and paused, "unknown modal close cannot unpause")
	await frame()
	check(game.get_snapshot().timer == frozen.timer and not game.pip.input_enabled and not game.van.input_enabled,
		"remaining modal freezes deadlines and actor ownership")
	check(game.close_modal(&"dialogue") and not paused and game.pip.input_enabled, "last modal restores correct owner")
	game.orders.settled.connect(observe_settlement)
	await deliver()
	check(settlements.size() == 1 and not settlement_observations.has(false), "one immutable committed settlement rejects reentrant duplicates/timeouts")
	check(initial.money == 0 and game.get_snapshot().money > 0, "earlier snapshot stays frozen after payment")
	check(game.hud._money.text == "$%d" % game.get_snapshot().money
		and game.hud._orders.text == "DELIVERIES  1", "HUD displays authoritative settlement")
	var old: Dictionary = settlements[0]
	game.restart()
	check(game.get_snapshot().generation > old.generation, "restart invalidates previous generation")
	check(not game.orders.settle(game.world.ids(), old.generation, old.order_id)
		and not game.orders.expire(game.world.ids(), old.generation, old.order_id), "old generation cannot settle or expire")
	var original: Array = game.houses.duplicate()
	game.houses.reverse() # isolated registry fixture; no scene/resource modification.
	check(game.force_destination("2 Marinara Way") and game.start_shift(), "stable destination command survives child-order change")
	check(game.get_snapshot().destination_id == "2 Marinara Way" and game.order_house == game.world.destination("2 Marinara Way"), "destination identity independent of legacy index")
	game.houses.assign(original)
	await destroy_game()
	# Reloads get new services/connections, not duplicate subscriptions on reset.
	for i in range(3):
		await create_game()
		settlements.clear()
		settlement_observations.clear()
		game.orders.settled.connect(observe_settlement)
		check(game.orders.get_signal_connection_list("settled").size() == 3, "one presenter, actor and fixture subscriber after reload %d" % i)
		game.start_shift()
		await deliver()
		check(settlements.size() == 1 and game.deliveries == 1 and game.active_order_id == 2, "one settlement and next order after reload %d" % i)
		Fixture.finish(game, true)
		check(game.get_snapshot().session_mode == "result" and game.get_snapshot().order_lifecycle == "closed", "result flow remains separate from closed ticket")
		game.restart()
		check(game.orders.get_signal_connection_list("settled").size() == 3 and game.money == 0, "reset does not reconnect signals")
		await destroy_game()
	# A restart inside the settlement signal must cancel old pending ticket creation.
	await create_game()
	game.start_shift()
	game.orders.settled.connect(func(_event: Dictionary) -> void: game.restart())
	await deliver()
	check(game.get_snapshot().session_mode == "title" and game.active_order_id == 0 and game.money == 0,
		"restart during committed event discards old generation's pending order")
	await destroy_game()
	# Ending a session during a callback also cancels pending work without reset.
	await create_game()
	game.start_shift()
	game.orders.settled.connect(func(_event: Dictionary) -> void: Fixture.finish(game, true))
	await deliver()
	check(game.get_snapshot().session_mode == "result" and game.active_order_id == 1,
		"ending session during settlement does not create a result-screen ticket")
	await destroy_game()
	print("PHASE 03: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
