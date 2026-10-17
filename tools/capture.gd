extends Node
## Scripted playtest + screenshot harness (autoload). Completely inert unless the
## game is started with  -- --capture-plan=res://tools/plans/<plan>.json
##
## Plan steps: {"at": seconds, "do": ...}
##   shot      {"name": "01_start"}                 save shots/<plan>_<name>.png
##   press     {"action": "interact"}               tap an input action
##   down/up   {"action": "move_forward"}           hold / release an action
##   walk_to   {"target": "door"|"pickup"|"van_left"|"van"|"park"} or {"pos":[x,y,z]}
##   drive_to  same targets, drives the van with the autopilot
##   place     {"node": "pip"|"van", "pos":[x,y,z], "yaw": deg}
##   camera    {"pos":[x,y,z], "look":[x,y,z], "fov": n}   freeze the rig (freecam)
##   follow    {}                                   hand the camera back to the rig
##   hud       {"visible": false}
##   start     {}                                   begin the shift (skip title)
##   order     {"index": 3}                         force the next order to a house
##   state     {}                                   print the game state to the log
##   time_scale {"v": 2.0}
##   quit      {}

var steps: Array = []
var idx := 0
var t := 0.0
var out_dir := "res://shots"
var plan_name := "plan"
var active := false
var game: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-plan="):
			path = a.substr("--capture-plan=".length())
	if path.is_empty():
		set_process(false)
		return
	if not FileAccess.file_exists(path):
		push_error("[capture] plan not found: " + path)
		set_process(false)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[capture] plan is not a JSON object: " + path)
		set_process(false)
		return
	steps = data.get("steps", [])
	out_dir = str(data.get("dir", "res://shots"))
	plan_name = str(data.get("name", "plan"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	steps.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	active = true
	print("[capture] plan '", plan_name, "' with ", steps.size(), " steps")


func _process(delta: float) -> void:
	if not active:
		return
	t += delta
	while idx < steps.size() and float(steps[idx].get("at", 0.0)) <= t:
		_execute(steps[idx])
		idx += 1


func _game() -> Node:
	if game == null or not is_instance_valid(game):
		game = get_tree().current_scene
	return game


func _pos_of(target: String) -> Vector3:
	var g := _game()
	match target:
		"pickup":
			return g.pickup_point.global_position
		"door":
			if g.order_house:
				return (g.order_house.get_node("Door") as Node3D).global_position
		"park":
			if g.order_house:
				return (g.order_house.get_node("Park") as Node3D).global_position
		"van":
			return g.van.global_position
		"van_left":
			return g.van.global_position + g.van.global_transform.basis.x * 2.0
		"shop_front":
			return Vector3(0, 0.1, 7.0)
	push_error("[capture] unknown target: " + target)
	return Vector3.ZERO


func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _execute(step: Dictionary) -> void:
	var what := str(step.get("do", ""))
	match what:
		"shot":
			_shot(str(step.get("name", "shot")))
		"press":
			_tap(str(step.get("action", "interact")))
		"down":
			_key(str(step.get("action", "")), true)
		"up":
			_key(str(step.get("action", "")), false)
		"walk_to":
			var p: Vector3 = _pos_of(str(step["target"])) if step.has("target") else _vec(step["pos"])
			if step.has("offset"):
				p += _vec(step["offset"])
			_game().pip.autopilot = p
			_game().van.autopilot = Vector3.INF
			print("[capture] walk_to ", p)
		"drive_to":
			var p: Vector3 = _pos_of(str(step["target"])) if step.has("target") else _vec(step["pos"])
			if step.has("offset"):
				p += _vec(step["offset"])
			_game().van.autopilot = p
			_game().pip.autopilot = Vector3.INF
			print("[capture] drive_to ", p)
		"place":
			var n: Node3D = _game().van if str(step.get("node", "pip")) == "van" else _game().pip
			n.global_position = _vec(step["pos"])
			if step.has("yaw"):
				n.rotation.y = deg_to_rad(float(step["yaw"]))
		"camera":
			var cam: Camera3D = _game().camera
			cam.set_physics_process(false)
			cam.global_position = _vec(step["pos"])
			cam.look_at(_vec(step["look"]), Vector3.UP)
			if step.has("fov"):
				cam.fov = float(step["fov"])
		"follow":
			_game().camera.set_physics_process(true)
		"hud":
			_game().hud.visible = bool(step.get("visible", true))
		"start":
			_game()._start_shift()
			print("[capture] shift started")
		"order":
			_game().forced_house = int(step.get("index", 0))
		"state":
			print("[capture] state: ", _game()._debug_state())
		"time_scale":
			Engine.time_scale = float(step.get("v", 1.0))
		"quit":
			print("[capture] done")
			get_tree().quit()
		_:
			push_warning("[capture] unknown step: " + what)


func _first_key(action: String) -> Key:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return KEY_NONE


func _key(action: String, pressed: bool) -> void:
	var k := _first_key(action)
	if k == KEY_NONE:
		push_error("[capture] no key bound to action " + action)
		return
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(action: String) -> void:
	_key(action, true)
	_key(action, false)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out_dir, plan_name, name]
	var err := img.save_png(path)
	print("[capture] shot ", path, " err=", err)
