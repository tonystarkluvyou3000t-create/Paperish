extends SceneTree
## Phase 06 acceptance: one interaction table drives both the HUD prompt and the
## action it describes, and conversations are data-driven transactions that commit
## exactly once - never on cancel, never twice, never after a restart.
## godot --headless --audio-driver Dummy --path . --script tools/phase06_checks.gd

const Fixture = preload("res://tools/dev_fixture.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")
const Interactions = preload("res://scripts/services/interaction_service.gd")
const Layers = preload("res://scripts/collision_layers.gd")

const RUN_SETTINGS := "user://phase06-run.cfg"
## An empty corner of the island: probe targets there compete with nothing.
const CORNER := Vector3(-30, 0.2, -24)

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
	for i in range(count):
		await physics_frame
	await process_frame


## Real key press and release through the viewport: menus match the logical
## keycode, gameplay actions the physical one, so synthetic input sets both.
func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press)
	await frame()
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	root.push_input(release)
	await frame()


func interact_key() -> Key:
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


func snap() -> Dictionary:
	return game.get_snapshot().to_dictionary()


func prompt_text() -> String:
	return game.presentation.prompt_text


func prompt_id() -> StringName:
	return game.presentation.prompt_id


func want(action: String, label: String) -> String:
	return "[%s]   %s" % [InputBindings.prompt(action), label]


func screen(id: String) -> Control:
	return game.menus.screen(id)


func find_control(id: String, control_name: String) -> Control:
	var scr := screen(id)
	if scr == null:
		return null
	return scr.find_child(control_name, true, false) as Control


func logical_size() -> Vector2:
	return game.get_viewport().get_visible_rect().size


func fits_across(rect: Rect2, slack := 2.0) -> bool:
	var logical := logical_size()
	return rect.position.x >= -slack and rect.end.x <= logical.x + slack


func scroll_reaches(id: String, control_name: String) -> bool:
	var scroll := find_control(id, "Scroll") as ScrollContainer
	var target := find_control(id, control_name)
	if scroll == null or target == null:
		return false
	scroll.scroll_vertical = 100000
	await frame()
	await frame()
	var rect := target.get_global_rect()
	var logical := logical_size()
	return rect.position.y >= -2.0 and rect.end.y <= logical.y + 2.0


## Where an actor stands to use a target's approach point.
func access(anchor: Node3D, local: Vector3) -> Vector3:
	return anchor.global_transform * local


func counter_spot() -> Vector3:
	return game.world.counter_access.global_position


func customer_spot() -> Vector3:
	return access(game.customer, Vector3(0, 0, -0.75))


func gossip_spot() -> Vector3:
	return access(game.gossip, Vector3(0, 0, -0.75))


func van_door_spot() -> Vector3:
	return access(game.van, Vector3(1.35, 0, -0.35))


## Places Pip and lets frames settle so the prompt reflects the new position.
func stand(where: Vector3, yaw := NAN) -> void:
	Fixture.place(game, "pip", where, yaw)
	await frames(2)


func ensure_shift() -> void:
	if game.session.flow == game.session.Flow.PLAYING and not game.session.roaming():
		return
	game.restart()
	await frame()
	game.start_shift()
	await frame()


func ensure_ticket_ready() -> void:
	if game.orders.lifecycle == game.orders.Lifecycle.AT_SHOP \
			and game.orders.ticket_state == game.orders.TicketState.PREPARING:
		game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())


func create_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	# Headless boots a 64x64 dummy window; pin the design resolution.
	game.get_window().size = Vector2i(1280, 720)
	await frame()
	game.set_order_seed(20261018)
	# Keep the suite off the real user://settings.cfg: same code path, own file.
	game.settings.configure(RUN_SETTINGS, true)
	game.settings.load_settings()
	await frame()


func destroy_game() -> void:
	game.settings.reset_to_defaults(false)
	game.queue_free()
	game = null
	await frame()
	await create_timer(0.2).timeout


func run() -> void:
	await create_game()
	if not game.world_ready:
		check(false, "world binds before phase 06 checks")
		finish()
		return
	await table_checks()
	await ambient_checks()
	await counter_checks()
	await facing_checks()
	await customer_checks()
	await van_checks()
	await lifetime_checks()
	await tie_break_checks()
	await roam_checks()
	await restart_checks()
	await text_checks()
	await layout_checks()
	await destroy_game()
	finish()


func finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SETTINGS))
	print("PHASE 06: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ the table
func table_checks() -> void:
	var table: Dictionary = game.interactions.entries()
	check(table.size() == 5, "the shipped world registers five named targets (%d)" % table.size())
	for id in [&"shop.counter", &"house.customer", &"van.driver", &"van.seat", &"plaza.gossip"]:
		check(game.interactions.has(id), "registered interaction: " + str(id))
	check(table[&"van.driver"].get("modes", []) == [game.actors.Mode.FOOT],
		"the driver door is a foot-only target")
	check(table[&"van.seat"].get("modes", []) == [game.actors.Mode.DRIVING],
		"the seat is a driving-only target")
	check(int(table[&"house.customer"].get("priority", 0)) > int(table[&"shop.counter"].get("priority", 0)),
		"the waiting customer outranks the counter")
	check(int(table[&"shop.counter"].get("priority", 0)) > int(table[&"plaza.gossip"].get("priority", 0)),
		"the counter outranks ambient chatter")
	check(not game.has_method("_try_pickup_or_deliver"),
		"the old distance-only interaction path is gone")
	check(game.interactions.prompt_view().has("text") and snap().has("prompt_id"),
		"prompt text and prompt id come from one query")
	for field in ["prompt_id", "dialogue_id", "dialogue_node", "dialogue_state",
			"dialogue_choices", "dialogue_busy", "dialogue_flags"]:
		check(snap().has(field), "the snapshot carries " + field)
	check(game.dialogue.problems().is_empty(), "the shipped conversations load without problems")
	check(game.shopkeeper != null and game.gossip != null and game.customer != null,
		"the placeholder people are in the scene")
	for who: Node3D in [game.shopkeeper, game.gossip, game.customer]:
		check(who.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"a placeholder never owns collision: " + str(who.name))
	check((Interactions.LOS_MASK & Layers.WORLD) == Layers.WORLD
		and (Interactions.LOS_MASK & Layers.VEHICLE) == 0
		and (Interactions.LOS_MASK & Layers.PLAYER) == 0,
		"line of sight is level geometry only: actors and vans never blind a prompt")
	var to_counter: Vector3 = game.pickup_point.global_position - game.shopkeeper.global_position
	to_counter.y = 0.0
	check(to_counter.length() < 1.6 and (-game.shopkeeper.global_basis.z).dot(to_counter.normalized()) > 0.9,
		"the shopkeeper stands at the service window facing the pick-up point")
	check(game.customer.visible == false, "nobody waits at a house before a ticket exists")
	check(not game.interact_available(), "the title cannot open a conversation")
	game.interact()
	check(not game.dialogue.active(), "a press under the title does nothing")


# ------------------------------------------------------------------ ambient chat
func ambient_checks() -> void:
	await ensure_shift()
	check(game.customer.visible, "a customer waits outside the ordered house during a shift")
	await stand(gossip_spot())
	check(prompt_id() == &"plaza.gossip", "the neighbour is the nearest target on the forecourt")
	check(prompt_text() == want("interact", "CHAT"),
		"the prompt names the action with the bound key (%s)" % prompt_text())
	check(game.interact_available(), "a shift allows interaction")
	game.interact()
	check(game.dialogue.active() and game.dialogue.conversation_id == "gossip",
		"the press opens the neighbour's conversation")
	check(game.paused and snap()["menu_screen"] == "dialogue",
		"a conversation freezes the world and shows its screen")
	check(snap()["dialogue_id"] == "gossip" and snap()["dialogue_node"] == "greet",
		"the snapshot names the open conversation and node")
	check(snap()["dialogue_state"] == "revealing", "the first frame reveals the line")
	check(not game.dialogue.advance(), "the press that opened the chat cannot also advance it")
	await frame()
	check(game.dialogue.advance(), "the next press completes the line")
	check(game.dialogue.state() == "choices" and game.dialogue.choices().size() == 2,
		"choices appear once the line is fully revealed")
	check(not game.dialogue.choose(-1) and not game.dialogue.choose(9),
		"an out-of-range choice is refused")
	check(game.dialogue.cancel(), "the neighbour chat can be left with esc")
	await frame()
	check(not game.dialogue.active() and not game.paused and snap()["menu_screen"] == "",
		"cancelling closes the chat and resumes the world")
	check(not game.dialogue.has_flag("nino.tip"), "a cancelled chat applies no effects")
	# Full keyboard route: open, reveal, pick the focused choice, commit.
	await stand(gossip_spot())
	await key(interact_key())
	check(game.dialogue.active() and snap()["dialogue_state"] == "revealing",
		"one key press opens the chat and never skips a line")
	await key(interact_key())
	check(game.dialogue.state() == "choices" and game.menus.focused_id() == "choice_0",
		"the first choice takes focus when the choices appear")
	await key(interact_key())
	check(snap()["dialogue_node"] == "hint", "the interact key picks the focused choice")
	await key(interact_key())
	check(game.dialogue.state() == "line", "the tip line reveals in full")
	await key(interact_key())
	await frame()
	check(not game.dialogue.active(), "the keyboard route reaches the committed end")
	check(game.dialogue.has_flag("nino.tip"), "the committed end sets its flag exactly once")
	check(game.hud._toast.text.contains("TIP"), "the tip toast rides the caption channel")
	# The flag changes the entry: the same neighbour now has nothing new to say.
	await stand(gossip_spot())
	game.interact()
	await frame()
	check(snap()["dialogue_node"] == "again", "a remembered conversation takes its other entry")
	await Fixture.finish_talk(game)
	await frame()
	check(not game.dialogue.active() and not game.paused, "the short chat still closes cleanly")


# ------------------------------------------------------------------ the counter
func counter_checks() -> void:
	await ensure_shift()
	await ensure_ticket_ready()
	var flags_before: int = snap()["dialogue_flags"]
	await stand(counter_spot())
	check(prompt_id() == &"shop.counter", "standing at the window targets the counter")
	check(prompt_text() == want("interact", "TAKE THE ORDER"),
		"the counter offers the order (%s)" % prompt_text())
	check(game.interactions.select().enabled, "an open counter is enabled")
	game.interact()
	check(game.dialogue.active() and game.dialogue.conversation_id == "shopkeeper",
		"the press opens the counter conversation")
	check(game.paused and snap()["menu_screen"] == "dialogue", "the world freezes for the order")
	check(not game.dialogue.end(), "a transaction cannot end on the frame it opened")
	await frame()
	check(game.dialogue.advance(), "the line completes")
	var line: String = game.dialogue.text()
	check(not line.contains("{{") and line.contains("Marinara"),
		"data tokens render into the line (%s)" % line)
	check(speaker_name() == "MONA", "the screen shows the speaker")
	var labels: Array[String] = game.dialogue.choices()
	check(labels.size() == 2 and labels[0] == "TAKE %d PIZZAS" % game.order_pizzas,
		"a token in a choice label renders too (%s)" % str(labels))
	game.dialogue.choose(1)
	await frame()
	check(not game.dialogue.active() and not game.paused, "an authored exit closes the chat")
	check(snap()["cargo_count"] == 0 and snap()["money"] == 0 and snap()["order_lifecycle"] == "at_shop",
		"leaving the counter changes nothing")
	check(snap()["menu_screen"] == "" and snap()["dialogue_id"] == "",
		"the conversation screen leaves the stack")
	# Esc cannot abandon a transaction: it pauses over it instead.
	game.interact()
	await frame()
	check(game.dialogue.cancellable == false, "the counter conversation is not cancellable")
	check(game.handle_back(), "esc over a transaction is consumed")
	check(game.dialogue.active() and snap()["menu_screen"] == "pause",
		"esc stacks the pause menu over the chat")
	check(&"dialogue" in game.session.reasons() and &"user_pause" in game.session.reasons(),
		"both reasons stay open")
	check(game.paused, "the world stays frozen")
	check(game.open_modal(&"fixture"), "a second reason can open on top")
	game.close_modal(&"fixture")
	await frame()
	check(snap()["menu_screen"] == "pause" and game.dialogue.active(),
		"closing an unrelated reason leaves the chat and its pause in place")
	check(game.menus.activate(&"options"), "settings open over the pause and the chat")
	await frames(2)
	check(snap()["menu_screen"] == "options" and game.dialogue.active() and game.paused,
		"settings over a conversation keep the world frozen")
	check(game.handle_back(), "esc leaves the settings screen")
	await frames(2)
	check(snap()["menu_screen"] == "pause" and game.dialogue.active() and game.paused,
		"the pause and the chat are still underneath the settings")
	check(game.handle_back(), "esc resumes out of the pause menu")
	await frame()
	check(snap()["menu_screen"] == "dialogue" and game.dialogue.active() and game.paused,
		"the chat is back on top, still frozen")
	check(game.interact_available(), "the chat keeps the interact key once its pause is closed")
	# The typewriter keeps its own pace, so one press finishes the line.
	await frame()
	game.dialogue.advance()
	await frame()
	check(game.dialogue.choices().size() == 2, "the chat returns to its choice node")
	game.dialogue.choose(0)
	await frame()
	check(snap()["dialogue_node"] == "handover" and game.dialogue.active(),
		"the taken branch runs before the commit")
	await Fixture.finish_talk(game)
	await frame()
	check(not game.dialogue.active() and not game.paused, "the handover commits and the world resumes")
	check(snap()["cargo_count"] == snap()["order_pizzas"] and snap()["order_lifecycle"] == "on_route",
		"the order is in Pip's hands")
	check(game.pip.carrying == game.order_pizzas, "the cargo visual follows the commit")
	check(snap()["deliveries"] == 0 and snap()["money"] == 0, "nothing was paid at the counter")
	check(snap()["dialogue_flags"] == flags_before, "the counter conversation adds no flags")
	# A closed counter explains itself and cannot double-charge.
	await stand(counter_spot())
	check(prompt_id() == &"shop.counter" and prompt_text() == "HANDS FULL",
		"a taken order reports the block (%s)" % prompt_text())
	game.interact()
	check(not game.dialogue.active(), "a blocked target never opens")
	check(game.dialogue.start("shopkeeper", &"shop.counter", game.shopkeeper),
		"the counter data still opens by hand")
	await frame()
	check(snap()["dialogue_node"] == "again", "hands full takes the defensive entry branch")
	await Fixture.finish_talk(game)
	await frame()
	check(snap()["cargo_count"] == snap()["order_pizzas"], "the closed counter is not a second pickup")


# ------------------------------------------------------------------ facing and sight
func facing_checks() -> void:
	var point := gossip_spot()
	var forward: Vector3 = -game.gossip.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot: Vector3 = point + forward * 2.5
	var face_point := yaw_towards(spot, point)
	await stand(spot, face_point)
	check(prompt_id() == &"plaza.gossip", "facing the neighbour shows the target")
	await stand(spot, face_point + 180.0)
	check(prompt_id() != &"plaza.gossip", "turning around drops a facing-gated target")
	await stand(point, face_point + 180.0)
	check(prompt_id() == &"plaza.gossip", "standing on the approach point is exempt from facing")
	# A wall in front of the approach point: the line of sight has to cross it.
	await stand(spot, face_point)
	check(prompt_id() == &"plaza.gossip", "an open approach point is visible")
	var wall := wall_between(game.gossip, 1.6)
	await frames(3)
	check(prompt_id() != &"plaza.gossip", "a wall between Pip and the neighbour hides the target")
	game.interact()
	check(not game.dialogue.active(), "a press through a wall opens nothing")
	wall.queue_free()
	await frames(3)
	check(prompt_id() == &"plaza.gossip", "removing the wall brings the prompt back")


## Yaw that makes an actor's forward axis point from one spot to another.
func yaw_towards(from: Vector3, to: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	return rad_to_deg(atan2(-d.x, -d.z))


func wall_between(anchor: Node3D, distance: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ProbeWall"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.0, 0.2)
	shape.shape = box
	body.add_child(shape)
	game.add_child(body)
	var basis := anchor.global_transform.basis
	body.global_transform = Transform3D(basis, anchor.global_position - basis.z * distance + Vector3(0, 1.0, 0))
	return body


# ------------------------------------------------------------------ the customer
func customer_checks() -> void:
	# The counter committed first, so the box is in Pip's hands and the door is live.
	var delivered_house: Node3D = game.order_house
	var delivered_customer_position: Vector3 = game.customer.global_position
	await stand(customer_spot())
	check(prompt_id() == &"house.customer", "the waiting customer is the door target")
	check(prompt_text() == want("interact", "DELIVER 2 PIZZAS"),
		"the door offers the delivery (%s)" % prompt_text())
	check(game.interactions.select().enabled, "the door is enabled with the right box")
	game.interact()
	await frame()
	check(game.dialogue.active() and game.dialogue.cancellable, "the street chat can be left")
	check(game.dialogue.speaker().get("name", "") == "THE CUSTOMER", "the customer speaks")
	check(game.handle_back(), "esc closes the cancellable chat")
	await frame()
	check(not game.dialogue.active() and not game.paused, "esc leaves the chat with nothing paid")
	check(snap()["deliveries"] == 0 and snap()["money"] == 0 and snap()["cargo_count"] > 0,
		"the pizzas are still in Pip's hands")
	# The wrong box explains itself and cannot be handed over.
	var wanted: int = game.order_pizzas
	game.orders.cargo_count = 1 if wanted != 1 else 2
	await frames(2)
	check(prompt_id() == &"house.customer" and prompt_text() == "WRONG ORDER",
		"the wrong box reports the block (%s)" % prompt_text())
	game.interact()
	check(not game.dialogue.active(), "the wrong order cannot finish the run")
	game.orders.cargo_count = wanted
	await frames(2)
	# Controller choice navigation: down moves the focus, the interact key takes
	# whatever is focused - here the second choice, which loses nothing.
	game.interact()
	await frame()
	game.dialogue.advance()
	await frames(2)
	check(game.dialogue.state() == "choices" and game.menus.focused_id() == "choice_0",
		"the door chat builds its choices with the first focused")
	await key(KEY_DOWN)
	check(game.menus.focused_id() == "choice_1", "down moves to the second choice")
	await key(interact_key())
	await frame()
	check(not game.dialogue.active() and snap()["deliveries"] == 0 and snap()["cargo_count"] > 0,
		"the focused second choice is the one that counts")
	# Now the real handover: reopen the door and take the first choice.
	game.interact()
	await frame()
	game.dialogue.advance()
	await frames(2)
	check(game.dialogue.choose(0), "the first choice is the accepted one")
	await frame()
	check(snap()["dialogue_node"] == "handover", "the accepted branch is entered")
	await Fixture.finish_talk(game)
	await frame()
	var paid: int = snap()["money"]
	check(snap()["deliveries"] == 1 and paid > 0 and snap()["cargo_count"] == 0,
		"handing over the box pays once and clears the cargo")
	check(snap()["order_lifecycle"] == "at_shop" and snap()["order_id"] > 1,
		"a fresh ticket follows the delivery")
	var next_house: Node3D = game.order_house
	var next_door := next_house.get_node_or_null("Door") as Node3D if next_house else null
	var customer_at_next_door: bool = next_house != null and next_house != delivered_house and next_door != null \
		and game.customer.global_position.distance_to(next_door.global_position) < 2.0 \
		and game.customer.global_position.distance_to(delivered_customer_position) > 1.0
	check(customer_at_next_door, "customer moves from the delivered house to the new ticket's door")
	# The same conversation cannot pay twice.
	check(game.dialogue.start("customer", &"house.customer", game.customer),
		"the door data can be forced open for the replay probe")
	await frame()
	await Fixture.finish_talk(game)
	await frame()
	check(snap()["deliveries"] == 1 and snap()["money"] == paid, "a replayed handover pays nothing")
	check(snap()["cargo_count"] == 0, "a replayed handover does not conjure cargo")
	check(not game.dialogue.active() and not game.paused, "the replay probe leaves a clean world")


# ------------------------------------------------------------------ the van
func van_checks() -> void:
	await ensure_shift()
	await stand(van_door_spot())
	check(prompt_id() == &"van.driver", "standing at the driver door targets the van")
	check(prompt_text() == want("interact", "DRIVE"), "the door offers the drive (%s)" % prompt_text())
	check(game.interact_available() and not game.driving, "the drive is offered on foot")
	game.interact()
	await frames(2)
	check(game.driving, "the press enters the van")
	check(prompt_id() == &"van.seat", "seated in a stopped van the seat is the target")
	check(prompt_text() == want("interact", "HOP OUT"),
		"a stopped van offers the exit (%s)" % prompt_text())
	game.van.speed = 6.0
	await frames(2)
	check(prompt_id() == &"van.seat" and prompt_text() == "STOP THE VAN TO EXIT",
		"a rolling van explains the block (%s)" % prompt_text())
	check(not game.interactions.select().enabled, "a rolling van is a blocked target")
	game.interact()
	check(game.driving, "a blocked exit does nothing")
	game.van.speed = 0.0
	await frames(2)
	game.interact()
	check(not game.driving, "braking to a stop then pressing leaves the van")


# ------------------------------------------------------------------ lifetimes
func lifetime_checks() -> void:
	await ensure_shift()
	var anchor := Node3D.new()
	game.add_child(anchor)
	anchor.global_position = CORNER + Vector3(0, 0, 0.75)
	check(game.interactions.register({
		"id": &"probe.ghost", "anchor": anchor, "access": Vector3(0, 0, -0.75), "range": 3.0,
		"label": "GHOST", "on_activate": func(_service: Node) -> bool: return true,
	}), "a probe target registers")
	await stand(CORNER)
	check(prompt_id() == &"probe.ghost" and prompt_text() == want("interact", "GHOST"),
		"the probe target drives the prompt on its own")
	check(game.interactions.activate(), "the probe target activates")
	anchor.queue_free()
	await frames(3)
	check(game.interactions.select().is_empty() and prompt_id() == &"",
		"a deleted anchor takes its prompt with it")
	check(not game.interactions.activate(), "a deleted anchor cannot fire an action")
	check(game.interactions.unregister(&"probe.ghost"), "the probe target unregisters")
	# A conversation dies with its target instead of hanging on a freed actor.
	var other := Node3D.new()
	game.add_child(other)
	other.global_position = CORNER
	check(game.interactions.register({
		"id": &"probe.talk", "anchor": other, "access": Vector3(0, 0, -0.75), "range": 3.0,
		"label": "TALK",
		"on_activate": func(_service: Node) -> bool:
			return game.dialogue.start("gossip", &"probe.talk", other),
	}), "a talking probe target registers")
	await stand(CORNER)
	game.interact()
	check(game.dialogue.active() and game.dialogue.busy_id == &"probe.talk",
		"the probe conversation is open")
	other.queue_free()
	await frames(3)
	check(not game.dialogue.active() and not game.paused and snap()["menu_screen"] == "",
		"the conversation closes when its target disappears")
	check(game.interactions.unregister(&"probe.talk"), "the talking probe unregisters")
	await frames(2)


# ------------------------------------------------------------------ tie-break
func selected_id() -> String:
	return str(game.interactions.select().get("id", ""))


func tie_break_checks() -> void:
	var anchor := Node3D.new()
	game.add_child(anchor)
	anchor.global_position = CORNER + Vector3(0, 0, 0.75)
	await stand(CORNER)
	check(game.interactions.register(probe(&"probe.a", anchor, 5, true)), "probe a registers")
	check(game.interactions.register(probe(&"probe.b", anchor, 5, true)), "probe b registers")
	check(selected_id() == "probe.a", "equal targets fall back to the id order")
	game.interactions.register(probe(&"probe.a", anchor, 5, false))
	check(selected_id() == "probe.b", "an enabled target beats a blocked one")
	game.interactions.register(probe(&"probe.a", anchor, 90, false))
	check(selected_id() == "probe.b", "eligibility outranks priority")
	game.interactions.register(probe(&"probe.a", anchor, 5, true))
	game.interactions.register(probe(&"probe.b", anchor, 9, true))
	check(selected_id() == "probe.b", "the higher priority wins between equals")
	var far := Node3D.new()
	game.add_child(far)
	far.global_position = CORNER + Vector3(0, 0, 2.75)
	game.interactions.register(probe(&"probe.b", far, 5, true))
	check(selected_id() == "probe.a", "the nearer approach point wins at equal priority")
	await frames(2)
	check(prompt_id() == &"probe.a", "the winner drives the prompt")
	game.interactions.unregister(&"probe.a")
	game.interactions.unregister(&"probe.b")
	anchor.queue_free()
	far.queue_free()
	await frames(2)


func probe(id: StringName, anchor: Node3D, priority: int, enabled: bool) -> Dictionary:
	return {
		"id": id, "anchor": anchor, "access": Vector3(0, 0, -0.75), "range": 3.0,
		"priority": priority, "label": "PROBE",
		"enabled": func() -> bool: return enabled,
		"on_activate": func(_service: Node) -> bool: return true,
	}


# ------------------------------------------------------------------ free roam
func roam_checks() -> void:
	game.restart()
	await frame()
	check(game.start_free_roam(), "free roam starts for the dormant-interaction checks")
	await stand(counter_spot())
	check(prompt_id() == &"shop.counter" and prompt_text() == "COUNTER CLOSED",
		"roam keeps the counter but says it is closed (%s)" % prompt_text())
	game.interact()
	check(not game.dialogue.active(), "a closed counter opens nothing in roam")
	check(snap()["cargo_count"] == 0 and snap()["deliveries"] == 0, "roam stays inert")
	check(not game.customer.visible, "no customer waits without a ticket")
	await stand(van_door_spot())
	check(prompt_id() == &"van.driver" and prompt_text() == want("interact", "DRIVE"),
		"the van still works in roam")
	game.interact()
	await frames(2)
	check(game.driving, "roam can still enter the van")
	game.restart()
	await frame()


# ------------------------------------------------------------------ restart
func restart_checks() -> void:
	await ensure_shift()
	await ensure_ticket_ready()
	await stand(counter_spot())
	game.interact()
	await frame()
	check(game.dialogue.active() and game.paused, "a chat is open before the restart")
	game.restart()
	await frame()
	check(not game.dialogue.active() and not game.paused, "a restart closes the conversation")
	check(snap()["menu_screen"] == "title" and snap()["dialogue_id"] == "",
		"the restart lands on a clean title")
	check(snap()["dialogue_flags"] == 0, "a restart clears conversation flags")
	await ensure_shift()
	await stand(customer_spot())
	check(prompt_text() == "NOTHING TO DELIVER", "an empty-handed press explains the wait")
	game.interact()
	check(not game.dialogue.active(), "nothing to deliver cannot open the door chat")


# ------------------------------------------------------------------ text policy
func text_checks() -> void:
	game.hud.toast("")
	game.hud.caption("NEW ORDER  ·  PROBE")
	check(game.hud._toast.text == "NEW ORDER  ·  PROBE", "with subtitles on, flavour captions show")
	game.settings.set_value("text/subtitles", false, false)
	game.hud.clear_toast()
	game.hud.caption("NEW ORDER  ·  PROBE")
	check(game.hud._toast.text == "", "with subtitles off, flavour captions are suppressed")
	game.hud.toast("TOO SLOW  ·  -1 PIZZA")
	check(game.hud._toast.text == "TOO SLOW  ·  -1 PIZZA", "essential feedback survives subtitles off")
	game.settings.set_value("text/subtitles", true, false)
	game.hud.clear_toast()
	game.settings.set_value("text/speed", 1.5, false)
	check(is_equal_approx(game.dialogue.text_speed(), 1.5), "text speed reaches the conversation")
	game.settings.set_value("text/speed", 1.0, false)
	check(is_equal_approx(game.dialogue.text_speed(), 1.0), "text speed returns to default")


# ------------------------------------------------------------------ layout
func layout_checks() -> void:
	await ensure_shift()
	await ensure_ticket_ready()
	game.get_window().size = Vector2i(1920, 1080)
	game.settings.set_value("video/ui_scale", 1.5, false)
	await frames(3)
	await stand(counter_spot())
	game.interact()
	await frame()
	await frame()
	game.dialogue.advance()
	await frames(2)
	var card := find_control("dialogue", "Card")
	check(card != null and card.is_visible_in_tree(), "the chat card is up at 150% scale")
	check(card != null and fits_across(card.get_global_rect()),
		"the chat card fits a 1920 view at 150% scale")
	var line := find_control("dialogue", "Line") as Label
	check(line != null and line.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"a long line wraps instead of running off the card")
	check(speaker_name() == "MONA", "the speaker chip survives the enlarged scale")
	var hint := find_control("dialogue", "Hint") as Label
	var leave := find_control("dialogue", "Leave") as Label
	check(hint != null and not hint.text.is_empty() and leave != null and not leave.text.is_empty(),
		"the chat teaches its keys")
	check(find_control("dialogue", "choice_0") != null, "the choices are built as buttons")
	check(await scroll_reaches("dialogue", "choice_1"),
		"the last choice stays reachable at 150% scale")
	check(game.dialogue.choose(1), "the enlarged chat takes an authored exit")
	await frame()
	check(not game.dialogue.active(), "the enlarged chat closes again")
	game.settings.set_value("video/ui_scale", 1.0, false)
	game.get_window().size = Vector2i(1280, 720)
	await frames(2)
	check(is_equal_approx(game.get_window().content_scale_factor, 1.0), "ui scale returns to 100%")


func speaker_name() -> String:
	var label := find_control("dialogue", "Speaker") as Label
	return label.text if label != null else ""
