extends Node
## Explicit developer-only scenario runner. See tools/SCENARIOS.md for schema.
## Inert unless -- --capture-plan=<JSON path> is present.

const Snapshot = preload("res://scripts/services/game_snapshot.gd")
const Fixture = preload("res://tools/dev_fixture.gd")
const SettingsService = preload("res://scripts/services/settings_service.gd")

const FIELDS := {
	"session_mode": TYPE_STRING, "order_lifecycle": TYPE_STRING, "actor_mode": TYPE_STRING, "generation": TYPE_INT,
	"mode": TYPE_STRING, "order_id": TYPE_INT, "order_count": TYPE_INT,
	"destination_id": TYPE_STRING, "cargo_inventory": TYPE_STRING,
	"ticket_state": TYPE_STRING, "preparation_remaining": TYPE_FLOAT, "ticket_customer": TYPE_STRING,
	"cargo_count": TYPE_INT, "order_pizzas": TYPE_INT, "deliveries": TYPE_INT,
	"van_cargo_count": TYPE_INT, "van_capacity": TYPE_INT,
	"money": TYPE_INT, "strikes": TYPE_INT, "driving": TYPE_BOOL, "paused": TYPE_BOOL,
	"timer": TYPE_FLOAT, "timer_max": TYPE_FLOAT, "speed": TYPE_FLOAT,
	"pip_control": TYPE_BOOL, "van_control": TYPE_BOOL, "van_stopped": TYPE_BOOL,
	"pip_autopilot": TYPE_BOOL, "van_autopilot": TYPE_BOOL,
	"pickup_distance": TYPE_FLOAT, "door_distance": TYPE_FLOAT, "park_distance": TYPE_FLOAT,
	"pip_x": TYPE_FLOAT, "pip_z": TYPE_FLOAT, "van_x": TYPE_FLOAT, "van_z": TYPE_FLOAT,
	"pip_visible": TYPE_BOOL, "pip_collision": TYPE_BOOL,
	"pip_motion": TYPE_FLOAT, "van_motion": TYPE_FLOAT, "tip": TYPE_INT, "world_ready": TYPE_BOOL,
	"camera_mode": TYPE_STRING, "camera_hint": TYPE_STRING,
	"play_mode": TYPE_STRING, "gameplay_visible": TYPE_BOOL,
	"menu_screen": TYPE_STRING, "menu_focused": TYPE_STRING, "timer_visible": TYPE_BOOL,
	"total_base": TYPE_INT, "total_pizza": TYPE_INT, "total_tip": TYPE_INT,
	"prompt_text": TYPE_STRING, "prompt_id": TYPE_STRING,
	"dialogue_id": TYPE_STRING, "dialogue_node": TYPE_STRING, "dialogue_state": TYPE_STRING,
	"dialogue_choices": TYPE_INT, "dialogue_busy": TYPE_STRING, "dialogue_flags": TYPE_INT,
	"nav_mode": TYPE_STRING, "nav_hint": TYPE_STRING, "nav_detail": TYPE_STRING, "nav_leg": TYPE_STRING,
	"nav_reachable": TYPE_BOOL, "nav_remaining_m": TYPE_FLOAT, "nav_eta_seconds": TYPE_FLOAT,
	"route_target": TYPE_STRING, "route_recomputes": TYPE_INT, "plan_ids": TYPE_STRING,
	"map_open": TYPE_BOOL, "waypoint_set": TYPE_BOOL, "unstuck_label": TYPE_STRING,
}
const TARGETS := ["door", "pickup", "van_left", "van", "park", "shop_front", "counter", "customer"]
const SCHEMA := {
	"start": [[], []], "restart": [[], []], "expire": [[], []], "retry_delivery": [[], []],
	"finish": [["win"], []], "state": [[], []], "quit": [[], []],
	"press": [["action"], []], "down": [["action"], []], "up": [["action"], []],
	"mouse_motion": [["dx", "dy"], []],
	"order": [[], ["index", "destination_id"]], "time_scale": [["v"], []], "shot": [["name"], []],
	"follow": [[], []], "hud": [["visible"], []],
	"menu": [["id"], []], "setting": [["key", "value"], []],
	"walk_to": [[], ["target", "pos", "offset"]], "drive_to": [[], ["target", "pos", "offset"]],
	"place": [["node"], ["target", "pos", "offset", "yaw"]],
	"camera": [["pos", "look"], ["fov"]],
	"talk": [[], ["expect", "pick"]],
	"assert": [["expect"], ["label"]], "wait": [["expect", "timeout"], ["label"]],
	"remember": [["name"], []],
}

var active := false
var game: Node
var out_dir := ""
var plan_name := "invalid"
var seed_value := 20261018
var snapshots := {}
var held := {}
var assertions := 0
var logical: Array = []
var elapsed := 0.0
var started_ms := 0
var wall_timeout := 120.0
var error_message := ""
var step_index := -1
var captured: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var path := ""
	var output_base := "user://test-runs"
	var seed_arg := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-plan="): path = arg.trim_prefix("--capture-plan=")
		elif arg.begins_with("--capture-output="): output_base = arg.trim_prefix("--capture-output=")
		elif arg.begins_with("--scenario-seed="): seed_arg = arg.trim_prefix("--scenario-seed=")
	if path.is_empty():
		set_process(false)
		return
	active = true
	started_ms = Time.get_ticks_msec()
	var data = null
	if FileAccess.file_exists(path):
		var parser := JSON.new()
		var err := parser.parse(FileAccess.get_file_as_string(path))
		if err == OK: data = parser.data
		else: error_message = "malformed JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
	else: error_message = "plan not found: " + path
	if error_message.is_empty(): error_message = validate_plan(data)
	if typeof(data) == TYPE_DICTIONARY:
		if typeof(data.get("name")) == TYPE_STRING and _safe_name(data.name): plan_name = data.name
		seed_value = int(data.get("seed", seed_value)) if _integer(data.get("seed", seed_value)) else seed_value
		if data.has("dir") and typeof(data.dir) == TYPE_STRING: output_base = data.dir + "/runs"
		wall_timeout = float(data.get("timeout", 120.0)) if _number(data.get("timeout", 120.0)) else 120.0
	if not seed_arg.is_empty():
		if not seed_arg.is_valid_int() or int(seed_arg) < 0: error_message = "scenario seed must be a nonnegative integer"
		else: seed_value = int(seed_arg)
	# A CLI output base takes precedence over old plans' dir values.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="): output_base = arg.trim_prefix("--capture-output=")
	out_dir = ProjectSettings.globalize_path(output_base).path_join("%s-%d-%d" % [plan_name, OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		error_message = "cannot create evidence directory: " + out_dir
	if not error_message.is_empty():
		_finish.call_deferred(false)
		return
	_run.call_deferred(data.steps)

func _process(delta: float) -> void:
	if not active: return
	elapsed += delta
	if float(Time.get_ticks_msec() - started_ms) / 1000.0 > wall_timeout and error_message.is_empty():
		error_message = "global wall-clock timeout"

func _number(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v))

func _integer(v) -> bool:
	return _number(v) and floor(float(v)) == float(v)

func _safe_name(v: String) -> bool:
	if v.is_empty(): return false
	for c in v:
		if not (c.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-"): return false
	return true

func _vector(v) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 3 and _number(v[0]) and _number(v[1]) and _number(v[2])

func validate_plan(data) -> String:
	if typeof(data) != TYPE_DICTIONARY: return "plan must be an object"
	for key in data:
		if key not in ["name", "seed", "dir", "steps", "timeout"]: return "unknown plan field: " + str(key)
	if not data.has("name") or typeof(data.name) != TYPE_STRING or not _safe_name(data.name): return "plan name must be a safe nonempty identifier"
	if data.has("seed") and (not _integer(data.seed) or data.seed < 0): return "seed must be a nonnegative integer"
	if data.has("dir") and typeof(data.dir) != TYPE_STRING: return "dir must be a string"
	if data.has("timeout") and (not _number(data.timeout) or data.timeout <= 0 or data.timeout > 600): return "plan timeout must be in (0,600] seconds"
	if not data.has("steps") or typeof(data.steps) != TYPE_ARRAY or data.steps.is_empty() or data.steps.size() > 2048: return "steps must be a nonempty array (max 2048)"
	var previous_at := 0.0
	var known_snapshots := {}
	for i in range(data.steps.size()):
		var step = data.steps[i]
		var prefix := "step %d: " % i
		if typeof(step) != TYPE_DICTIONARY or typeof(step.get("do")) != TYPE_STRING: return prefix + "requires string do"
		var kind: String = step.do
		if not SCHEMA.has(kind): return prefix + "unknown step: " + kind
		for field in SCHEMA[kind][0]:
			if not step.has(field): return prefix + "missing " + field
		for field in step:
			if field not in ["do", "at"] and field not in SCHEMA[kind][0] and field not in SCHEMA[kind][1]: return prefix + "unknown field " + str(field)
		if step.has("at"):
			if not _number(step.at) or step.at < previous_at: return prefix + "at must be nonnegative and monotonic"
			previous_at = float(step.at)
		if step.has("label") and typeof(step.label) != TYPE_STRING: return prefix + "label must be a string"
		if kind in ["press", "down", "up"]:
			if typeof(step.action) != TYPE_STRING or not InputMap.has_action(step.action) or _action_event(step.action) == null:
				return prefix + "unknown keyboard/mouse action: " + str(step.action)
		if kind == "mouse_motion":
			if not _number(step.dx) or not _number(step.dy): return prefix + "dx/dy must be finite numbers"
		if kind == "order":
			if step.has("index") == step.has("destination_id"): return prefix + "order needs exactly one index/destination_id"
			if step.has("index") and (not _integer(step.index) or step.index < 0): return prefix + "index must be a nonnegative integer"
			if step.has("destination_id") and (typeof(step.destination_id) != TYPE_STRING or step.destination_id.is_empty()): return prefix + "destination_id must be a nonempty string"
		if kind == "time_scale" and (not _number(step.v) or step.v <= 0 or step.v > 8): return prefix + "v must be in (0,8]"
		if kind in ["shot", "remember"]:
			if typeof(step.name) != TYPE_STRING or not _safe_name(step.name): return prefix + "name must be a safe identifier"
			if kind == "remember": known_snapshots[step.name] = true
		if kind == "finish" and typeof(step.win) != TYPE_BOOL: return prefix + "win must be boolean"
		if kind == "hud" and typeof(step.visible) != TYPE_BOOL: return prefix + "visible must be boolean"
		if kind == "menu" and (typeof(step.id) != TYPE_STRING or step.id.is_empty()): return prefix + "id must be a nonempty string"
		if kind == "setting":
			if typeof(step.key) != TYPE_STRING or not SettingsService.DEFAULTS.has(step.key): return prefix + "unknown setting key: " + str(step.key)
			if typeof(step.value) == TYPE_BOOL or typeof(step.value) == TYPE_STRING: pass
			elif not _number(step.value): return prefix + "setting value must be a number, boolean or choice string"
		if kind in ["walk_to", "drive_to", "place"]:
			if step.has("target") == step.has("pos"): return prefix + "requires exactly one of target/pos"
			if step.has("target") and (typeof(step.target) != TYPE_STRING or step.target not in TARGETS): return prefix + "unknown target"
			if kind == "place" and (typeof(step.node) != TYPE_STRING or step.node not in ["pip", "van"]): return prefix + "node must be pip or van"
		for field in ["pos", "look", "offset"]:
			if step.has(field) and not _vector(step[field]): return prefix + field + " must be three finite numbers"
		if step.has("yaw") and not _number(step.yaw): return prefix + "yaw must be numeric"
		if step.has("fov") and (not _number(step.fov) or step.fov < 1 or step.fov > 179): return prefix + "fov must be in [1,179]"
		if kind in ["wait", "assert", "talk"]:
			if kind == "wait" and (not _number(step.timeout) or step.timeout <= 0 or step.timeout > 120): return prefix + "wait timeout must be in (0,120] seconds"
			if step.has("expect"):
				var problem := _validate_expect(step.expect, known_snapshots)
				if not problem.is_empty(): return prefix + problem
			if kind != "talk" and not step.has("expect"): return prefix + "missing expect"
		if kind == "talk" and step.has("pick") and (not _integer(step.pick) or step.pick < 0):
			return prefix + "pick must be a nonnegative integer"
		if kind == "quit" and i != data.steps.size() - 1: return prefix + "quit must be the final step"
	if data.steps[-1].do != "quit": return "plan must end with quit"
	return ""

func _validate_expect(expect, known: Dictionary) -> String:
	if typeof(expect) != TYPE_DICTIONARY or expect.is_empty(): return "expect must be a nonempty object"
	for field in expect:
		if not FIELDS.has(field): return "unknown diagnostic field: " + str(field)
		var condition = expect[field]
		if typeof(condition) == TYPE_DICTIONARY:
			if condition.get("op") not in ["eq", "ne", "lt", "lte", "gt", "gte"]: return "invalid comparison op for " + field
			if condition.has("value") == condition.has("saved"): return "comparison needs exactly one value/saved"
			for key in condition:
				if key not in ["op", "value", "saved"]: return "unknown comparison field " + str(key)
			if condition.op not in ["eq", "ne"] and FIELDS[field] not in [TYPE_INT, TYPE_FLOAT]: return "ordered comparison requires numeric field"
			if condition.has("saved"):
				if typeof(condition.saved) != TYPE_STRING: return "saved reference must be a string"
				var parts: PackedStringArray = condition.saved.split(".")
				if parts.size() != 2 or not known.has(parts[0]) or not FIELDS.has(parts[1]) or FIELDS[parts[1]] != FIELDS[field]: return "unknown or incompatible saved reference " + condition.saved
				continue
			condition = condition.value
		var expected_type: int = FIELDS[field]
		if expected_type == TYPE_INT:
			if not _integer(condition): return "integer expected for " + field
		elif expected_type == TYPE_FLOAT:
			if not _number(condition): return "number expected for " + field
		elif typeof(condition) != expected_type: return "wrong type for " + field
	return ""

func _run(steps: Array) -> void:
	await get_tree().process_frame
	game = get_tree().current_scene
	if game == null or not game.world_ready:
		error_message = "main scene/world is not ready"
		await _finish(false)
		return
	game.set_order_seed(seed_value)
	print("[capture] plan=%s seed=%d steps=%d" % [plan_name, seed_value, steps.size()])
	for i in range(steps.size()):
		step_index = i
		var step: Dictionary = steps[i]
		while elapsed < float(step.get("at", 0.0)) and error_message.is_empty():
			await get_tree().process_frame
		if not error_message.is_empty(): break
		await _execute(step)
		if not error_message.is_empty(): break
		if step.do == "quit": break
		await get_tree().physics_frame
		await get_tree().process_frame
	await _finish(error_message.is_empty())

func _matches(expect: Dictionary) -> String:
	var state: Dictionary = game.get_snapshot().to_dictionary()
	for field in expect:
		var condition = expect[field]
		var op := "eq"
		var value = condition
		if typeof(condition) == TYPE_DICTIONARY:
			op = condition.op
			if condition.has("saved"):
				var parts: PackedStringArray = condition.saved.split(".")
				value = snapshots[parts[0]][parts[1]]
			else: value = condition.value
		var actual = state[field]
		var ok := false
		match op:
			"eq": ok = actual == value
			"ne": ok = actual != value
			"lt": ok = actual < value
			"lte": ok = actual <= value
			"gt": ok = actual > value
			"gte": ok = actual >= value
		if not ok: return "%s actual=%s expected %s %s" % [field, str(actual), op, str(value)]
	return ""

func _execute(step: Dictionary) -> void:
	match step.do:
		"assert", "wait":
			var deadline := Time.get_ticks_msec() + int(float(step.get("timeout", 0)) * 1000)
			var problem := _matches(step.expect)
			while not problem.is_empty() and step.do == "wait" and Time.get_ticks_msec() < deadline and error_message.is_empty():
				await get_tree().process_frame
				problem = _matches(step.expect)
			if not problem.is_empty():
				error_message = "%s '%s': %s" % [step.do, step.get("label", ""), problem]
			elif error_message.is_empty():
				assertions += 1
				_record(step.get("label", step.do))
		"remember": snapshots[step.name] = game.get_snapshot().to_dictionary().duplicate(true)
		"press":
			_key(step.action, true)
			await get_tree().process_frame
			_key(step.action, false)
		"down": _key(step.action, true)
		"up": _key(step.action, false)
		"mouse_motion":
			var motion := InputEventMouseMotion.new()
			motion.position = Vector2(640, 360)
			motion.relative = Vector2(float(step.dx), float(step.dy))
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
		"order":
			if step.has("destination_id"):
				if not game.force_destination(step.destination_id): error_message = "destination ID not registered"
			elif not game.force_destination_index(int(step.index)): error_message = "destination index out of range"
		"start": game.start_shift()
		"restart": game.restart()
		"menu":
			if game.menus == null or not game.menus.activate(StringName(step.id)):
				error_message = "menu id not accepted: " + str(step.id)
		"setting":
			# Scenario-time override: applies live but never touches user://settings.cfg.
			if game.settings == null or step.key not in SettingsService.DEFAULTS:
				error_message = "setting not accepted: %s" % str(step.key)
			else:
				game.settings.set_value(step.key, step.value, false)
				var applied: Variant = game.settings.value(step.key)
				var matches := false
				if typeof(step.value) == TYPE_STRING:
					matches = str(applied) == str(step.value)
				else:
					matches = is_equal_approx(float(applied), float(step.value))
				if not matches:
					error_message = "setting value not accepted: %s" % str(step.value)
		"expire":
			Fixture.expire(game)
		"talk":
			# Drives an open conversation to its committed end with the regular
			# player actions, then asserts where the world landed.
			var pick := int(step.get("pick", 0))
			var guard := 0
			while game.dialogue.active() and guard < 64 and error_message.is_empty():
				guard += 1
				if game.dialogue.revealing() or game.dialogue.choices().is_empty():
					game.dialogue.advance()
				else:
					game.dialogue.choose(pick)
				await get_tree().process_frame
			if game.dialogue.active():
				error_message = "talk '%s': conversation never ended" % step.get("expect", "")
			elif step.has("expect"):
				var problem := _matches(step.expect)
				if not problem.is_empty():
					error_message = "talk: " + problem
				else:
					assertions += 1
					_record("talk")
			else:
				_record("talk")
		"retry_delivery": Fixture.retry_delivery(game)
		"finish": Fixture.finish(game, step.win)
		"state": _record("state")
		"time_scale": Engine.time_scale = float(step.v)
		"place", "walk_to", "drive_to":
			var pos: Vector3 = _position(step)
			if not error_message.is_empty(): return
			if step.do == "place":
				Fixture.place(game, step.node, pos, float(step.get("yaw", NAN)))
			else: Fixture.autopilot(game, "pip" if step.do == "walk_to" else "van", pos)
		"shot": await _shot(step.name)
		"camera":
			game.camera.set_physics_process(false)
			game.camera.global_position = _vec(step.pos)
			game.camera.look_at(_vec(step.look), Vector3.UP)
			if step.has("fov"): game.camera.fov = float(step.fov)
		"follow": game.camera.set_physics_process(true)
		"hud": game.hud.visible = step.visible
		"quit": pass

func _record(label: String) -> void:
	var d: Dictionary = game.get_snapshot().to_dictionary()
	var record := {"label": label}
	for field in ["mode", "order_id", "order_count", "destination_id", "cargo_inventory", "cargo_count", "van_cargo_count", "van_capacity", "order_pizzas", "deliveries", "money", "strikes", "driving", "paused",
			"play_mode", "session_mode", "gameplay_visible", "menu_screen", "menu_focused", "order_lifecycle", "ticket_state", "timer_visible",
			"nav_mode", "nav_hint", "nav_leg", "nav_reachable", "route_target", "plan_ids", "map_open", "waypoint_set",
			"prompt_id", "dialogue_id"]:
		record[field] = d.get(field)
	logical.append(record)
	print("[capture] ", JSON.stringify(record))

func _position(step: Dictionary) -> Vector3:
	var pos := Vector3.ZERO
	if step.has("pos"): pos = _vec(step.pos)
	else:
		match step.target:
			"pickup": pos = game.pickup_point.global_position
			"counter": pos = game.world.counter_access.global_position
			"customer":
				if not game.customer.visible:
					error_message = "target requires a waiting customer: customer"
					return Vector3.ZERO
				pos = game.customer.global_transform * Vector3(0, 0, -0.75)
			"door", "park":
				if game.order_house == null:
					error_message = "target requires an active destination: " + str(step.target)
					return Vector3.ZERO
				pos = game.order_house.get_node("Door" if step.target == "door" else "Park").global_position
			"van": pos = game.van.global_position
			"van_left": pos = game.van.global_position + game.van.global_basis.x * 2.0
			"shop_front":
				var entrance: Node3D = game.world.marker("poi:shop_front_approach")
				if entrance == null:
					error_message = "shop front approach marker is not registered"
					return Vector3.ZERO
				pos = entrance.global_position
	if step.has("offset"): pos += _vec(step.offset)
	return pos

func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _first_key(action: String) -> Key:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey: return ev.physical_keycode
	return KEY_NONE

## First keyboard or mouse event of an action, for press/down/up simulation.
## Gamepad-only actions have no simulation path here, so plans must pick a bound
## key or mouse button for press/down/up.
func _action_event(action: String) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null

func _key(action: String, pressed: bool) -> void:
	var base := _action_event(action)
	var event: InputEvent
	if base is InputEventKey:
		var source := base as InputEventKey
		var key := InputEventKey.new()
		# Real keyboards report the logical and the physical key together. Menus
		# activate the focused button through the builtin ui_accept action, which
		# matches on the logical keycode, so injected input sets both fields.
		key.keycode = source.keycode if source.keycode != KEY_NONE else source.physical_keycode
		key.physical_keycode = source.physical_keycode if source.physical_keycode != KEY_NONE else source.keycode
		event = key
	elif base is InputEventMouseButton:
		var button := InputEventMouseButton.new()
		button.button_index = (base as InputEventMouseButton).button_index
		event = button
	else:
		return
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if pressed: held[action] = true
	else: held.erase(action)

func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[capture] SKIP visual capture in headless mode: ", shot_name)
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	if img == null or img.is_empty() or img.save_png(path) != OK:
		error_message = "screenshot failed: " + path
		return
	captured.append(path)
	print("[capture] image ", path)

func _finish(success: bool) -> void:
	active = false
	# Validation can fail before the main scene is assigned to this runner.
	# Still own and release that scene before exiting, including its audio.
	if not is_instance_valid(game):
		await get_tree().process_frame
		game = get_tree().current_scene
	var released_actions := held.keys()
	for action in held.keys():
		_key(action, false)
		Input.action_release(action)
	held.clear()
	var still_pressed: Array = []
	for action in released_actions:
		if Input.is_action_pressed(action): still_pressed.append(action)
	Engine.time_scale = 1.0
	get_tree().paused = false
	if is_instance_valid(game) and game.has_method("get_diagnostics"):
		Fixture.cleanup(game)
	var report := {
		"name": plan_name, "seed": seed_value, "success": success,
		"step": step_index, "error": error_message, "assertions": assertions,
		"logical": logical, "images": captured,
		"cleanup": {"paused": get_tree().paused, "time_scale": Engine.time_scale, "held_actions": held.keys(), "pressed_actions": still_pressed},
	}
	var path := out_dir.path_join("result.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	else:
		success = false
		error_message += " cannot save result: " + path
	print("CAPTURE_RESULT ", path)
	if not success: printerr("SCENARIO FAIL step=%d %s" % [step_index, error_message])
	else: print("SCENARIO PASS assertions=", assertions)
	# Free the tested scene and let Dummy audio's real-time mix cleanup finish.
	if is_instance_valid(game):
		game.queue_free()
		game = null
	await get_tree().process_frame
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit(0 if success else 1)
