extends SceneTree
## Real-input Phase 10 traversal. It follows authored walkway/road waypoints by
## pressing the normal movement actions; neither actor is teleported or put on autopilot.

const Fixture = preload("res://tools/dev_fixture.gd")
var game: Node
var checks := 0
var failures: Array[String] = []
var held: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures.append(message)
		printerr("FAIL ", message)

func frame() -> void:
	await process_frame

func set_actions(wanted: Array[String]) -> void:
	for action in held:
		if action not in wanted: Input.action_release(action)
	for action in wanted:
		if action not in held: Input.action_press(action)
	held = wanted.duplicate()

func release_all() -> void:
	for action in held: Input.action_release(action)
	held.clear()

func walk_to(target: Vector3, limit := 1500, reach := 0.85) -> bool:
	for _i in range(limit):
		var delta: Vector3 = target - game.pip.global_position
		delta.y = 0.0
		if delta.length() < reach:
			release_all()
			return absf(game.pip.global_position.y) < 0.35
		var forward: Vector3 = -game.camera.global_transform.basis.z
		var right: Vector3 = game.camera.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		var local_forward: float = delta.dot(forward)
		var local_right: float = delta.dot(right)
		var actions: Array[String] = []
		if local_forward > 0.18: actions.append("move_forward")
		elif local_forward < -0.18: actions.append("move_back")
		if local_right > 0.18: actions.append("move_right")
		elif local_right < -0.18: actions.append("move_left")
		set_actions(actions)
		await frame()
	release_all()
	return false

func walk_graph(from_id: String, to_id: String) -> bool:
	var route: Dictionary = game.world.graph.pedestrian_route(from_id, to_id)
	if not route.get("reachable", false):
		printerr("PHASE 10 route: pedestrian graph unreachable ", from_id, " -> ", to_id)
		return false
	for node_id in route.path:
		var node: Dictionary = game.world.graph.pedestrian_nodes.get(node_id, {})
		if node.is_empty(): return false
		var p: Array = node.get("position", [])
		if p.size() != 2: return false
		if not await walk_to(Vector3(float(p[0]), 0.0, float(p[1]))):
			printerr("PHASE 10 route: on-foot input stalled at ", node_id,
				" actual=", game.pip.global_position)
			return false
	return true

func drive_to(target: Vector3, limit := 900) -> bool:
	for _i in range(limit):
		var delta: Vector3 = target - game.van.global_position
		delta.y = 0.0
		if delta.length() < 7.0:
			release_all()
			return game.van.global_position.y > -0.45 and game.van.global_position.y < 0.35
		var desired_yaw := atan2(delta.x, delta.z)
		var angle := wrapf(desired_yaw - game.van.rotation.y, -PI, PI)
		var actions: Array[String] = []
		if absf(angle) > 0.10:
			actions.append("move_left" if angle > 0.0 else "move_right")
		if absf(angle) > 0.82 and game.van.speed > 4.0:
			actions.append("move_back")
		else:
			actions.append("move_forward")
		set_actions(actions)
		await frame()
	release_all()
	return false

func run() -> void:
	InputMap.load_from_project_settings()
	var van_only := OS.get_cmdline_user_args().has("--phase10-van-only")
	var game_scene: PackedScene = ResourceLoader.load(
		"res://scenes/game.tscn", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	game = game_scene.instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	Engine.time_scale = 2.0
	game.camera.reduced_motion = true
	game.camera.yaw = 0.0
	check(game.start_shift(), "normal shift starts for real-input traversal")
	await frame()
	var foot_ok := true
	if not van_only:
		var foot_loop := ["poi:cedar_green", "poi:east_pier", "poi:summit_overlook",
			"poi:market_square", "poi:pizza_plaza"]
		var current := "spawn:player"
		for destination in foot_loop:
			var ok: bool = await walk_graph(current, destination)
			check(ok, "Pip traverses on foot to " + str(destination))
			if not ok: foot_ok = false; break
			current = destination
		if foot_ok:
			check(await walk_graph(current, "spawn:player"), "Pip completes the five-district foot loop")
	# Approach from the rear, then circle around the van's front to the driver side.
	# Each waypoint is reached with ordinary directional input around the collider.
	var van_approach := [Vector3(0.0, 0.0, 8.25), Vector3(-2.65, 0.0, 4.1),
		Vector3(-2.65, 0.0, 1.85), Vector3(-2.65, 0.0, 0.0),
		Vector3(2.35, 0.0, 0.0), Vector3(1.2, 0.0, 0.2)]
	var foot_to_van := true
	for point in van_approach:
		if not await walk_to(point, 360):
			foot_to_van = false
			break
	check(foot_to_van, "Pip reaches the van through ordinary movement input")
	check(game.presentation.prompt_id == &"van.driver", "the van driver interaction is physically in range")
	if game.presentation.prompt_id == &"van.driver": game.interact()
	check(game.driving, "the normal driver interaction seats Pip")
	var road_loop := [Vector3(80, 0, 0), Vector3(145, 0, 0), Vector3(145, 0, 35),
		Vector3(125, 0, 35), Vector3(125, 0, 70), Vector3(40, 0, 70),
		Vector3(40, 0, 95), Vector3(-40, 0, 95), Vector3(-40, 0, 70),
		Vector3(-80, 0, 70), Vector3(-80, 0, -40), Vector3(-80, 0, -70),
		Vector3(-80, 0, -100), Vector3(0, 0, -100), Vector3(0, 0, -110),
		Vector3(0, 0, -45), Vector3(13.2, 0, -45), Vector3(13.2, 0, 0),
		Vector3(0, 0, 0)]
	var van_ok: bool = game.driving
	for i in road_loop.size():
		var p: Vector3 = road_loop[i]
		var arrived: bool = await drive_to(p)
		var district := "waterfront" if i <= 4 else "market" if i <= 9 else "residential" if i <= 12 else "hillside" if i <= 15 else "downtown"
		if not arrived or game.van.global_position.distance_to(Vector3(p.x, game.van.global_position.y, p.z)) >= 10.0:
			print("PHASE 10 route: van checkpoint=%d target=%s actual=%s yaw=%.2f speed=%.2f arrived=%s" % [
				i, str(p), str(game.van.global_position), game.van.rotation.y, game.van.speed, str(arrived)])
		check(arrived and game.van.global_position.distance_to(Vector3(p.x, game.van.global_position.y, p.z)) < 10.0,
			"van follows road inputs through " + district + " checkpoint %d" % i)
		if not arrived: van_ok = false; break
		if not (absf(game.van.global_position.x) < 160.0 and absf(game.van.global_position.z) < 120.0):
			van_ok = false
			check(false, "van remains inside the authored island boundary")
			break
	check(van_ok and game.van.global_position.y > -0.45 and game.van.global_position.y < 0.35,
		"van stays supported while completing the five-district road loop")
	release_all()
	Engine.time_scale = 1.0
	if game:
		Fixture.cleanup(game)
		game.queue_free()
		game = null
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	print("PHASE 10 ROUTE: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _initialize() -> void:
	call_deferred("run")
