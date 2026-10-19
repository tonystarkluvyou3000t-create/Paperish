extends SceneTree
## Phase 11 measured drive: ordinary steering and throttle input follows each
## planned drive leg with the throttle capped at the conservative route speed, so
## the published ETA can be compared against a drive that actually happened. After
## parking, ordinary forward input walks the planned pedestrian leg to the
## customer's door. The table this prints is the measured-vs-estimated record
## quoted in the handoff.
##
## Nothing is teleported onto a road: the fixture only resets the run, forces the
## next ticket and seats the player in the van, exactly like the phase 10
## traversal fixture. Every metre after that comes from real movement actions.

const Fixture = preload("res://tools/dev_fixture.gd")

var game: Node
var checks := 0
var failures: Array[String] = []
var held: Array[String] = []
## Every distinct live hint seen across the measured drives.
var hints: Array[String] = []
## Whether any guidance hint appeared during the current walk-up.
var walk_spoke := false

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


## Sim seconds elapsed since a physics-frame mark. The harness runs the world at
## `Engine.time_scale`, which scales the clock the physics ticks advance, so the
## tick count is converted with the same factor; each measured drive is also
## cross-checked against the game's own deadline clock below.
func _sim_seconds(mark: int) -> float:
	return float(Engine.get_physics_frames() - mark) / 60.0 * Engine.time_scale


## Ordinary driving input toward one point, never above the conservative speed.
## Records every distinct live hint along the way. Returns sim seconds, or -1 on a
## stall.
func steer_to(target: Vector3, limit := 2400, reach := 5.0) -> float:
	var cap := float(game.balance.conservative_route_speed)
	var start := Engine.get_physics_frames()
	for _i in range(limit):
		var hint := str(game.routes.guidance().get("hint", ""))
		if not hint.is_empty() and not hints.has(hint):
			hints.append(hint)
		var delta: Vector3 = target - game.van.global_position
		delta.y = 0.0
		if delta.length() < reach:
			release_all()
			return _sim_seconds(start)
		var desired_yaw := atan2(delta.x, delta.z)
		var angle := wrapf(desired_yaw - game.van.rotation.y, -PI, PI)
		var actions: Array[String] = []
		if absf(angle) > 0.10:
			actions.append("move_left" if angle > 0.0 else "move_right")
		# Throttle cap: the pedal is held only up to the conservative speed, then
		# released into the brake. Only one pedal at a time - holding both would
		# read as a neutral axis and coast. A safe drive therefore never outruns
		# the speed the estimate is allowed to assume.
		actions.append("move_back" if game.van.speed > cap else "move_forward")
		set_actions(actions)
		await frame()
	release_all()
	return -1.0


## Holds forward with the camera aimed at `target` until Pip is within `reach`
## metres of it or the frame budget runs out. Real movement input throughout, and
## every distinct live hint seen on the way is recorded.
func walk_toward(target: Vector3, reach: float, limit: int) -> bool:
	for _i in range(limit):
		var hint := str(game.routes.guidance().get("hint", ""))
		if not hint.is_empty():
			walk_spoke = true
			if not hints.has(hint):
				hints.append(hint)
		var delta: Vector3 = target - game.pip.global_position
		delta.y = 0.0
		if delta.length() <= reach:
			release_all()
			return true
		game.camera.yaw = atan2(delta.x, delta.z) + PI
		set_actions(["move_forward"])
		await frame()
	release_all()
	return false


## Walks to a target and, when the straight line stalls, steps sideways around
## whatever is in the way before trying again - the parked van sits between the
## exit spot and the door on some pads, and a player just walks around it. Bounded
## to three attempts so a genuinely blocked door still fails the check.
func walk_with_detours(target: Vector3, reach: float, limit: int) -> bool:
	if await walk_toward(target, reach, limit):
		return true
	for _attempt in range(3):
		var away: Vector3 = game.pip.global_position - target
		away.y = 0.0
		if away.length() < 0.01:
			return false
		var side := Vector3(-away.z, 0.0, away.x).normalized()
		var stepped := await walk_toward(game.pip.global_position + side * 3.0, 1.2, 150)
		if not stepped:
			stepped = await walk_toward(game.pip.global_position - side * 3.0, 1.2, 150)
		if not stepped:
			return false
		if await walk_toward(target, reach, limit):
			return true
	return false


## Walks the planned pedestrian leg waypoint by waypoint from the point nearest to
## Pip, then makes the last stride to the door marker itself.
func walk_to_door(route: Dictionary) -> bool:
	game.camera.reduced_motion = true
	var points: Array = route.walk_points
	if points.size() < 2:
		points = [route.door_position]
	var first := 0
	var best := INF
	for index in points.size():
		var point: Vector3 = points[index]
		var flat := Vector2(point.x - game.pip.global_position.x, point.z - game.pip.global_position.z)
		if flat.length() < best:
			best = flat.length()
			first = index
	for index in range(first, points.size()):
		var reach := 1.6 if index < points.size() - 1 else 1.2
		if not await walk_with_detours(points[index], reach, 300):
			return false
	return await walk_with_detours(route.door_position, 1.1, 240)


## Holds the brake until the van is stopped: the exit interaction requires it.
func brake_to_stop(limit := 240) -> bool:
	set_actions(["move_back"])
	for _i in range(limit):
		if absf(game.van.speed) <= 0.2:
			break
		await frame()
	release_all()
	return absf(game.van.speed) <= 0.25


## One fresh run per destination: the ticket is forced to that address, collected
## at the counter, then the van drives the game's own planned leg.
func measure(address_id: String, district: String) -> Dictionary:
	game.restart()
	await frame()
	game.force_destination(address_id)
	check(game.start_shift(), "a shift starts with the forced %s ticket" % district)
	await frame()
	game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())
	check(game.orders.can_pickup() and game.orders.pickup(), "the %s ticket is collected at the counter" % district)
	# Seat the driver through the normal interaction: Pip is placed beside the
	# parked van (the walk-up is the phase 10 traversal's subject, not this one)
	# and `enter` enables the van's own movement input.
	Fixture.place(game, "pip", game.world.van_spawn.global_position + Vector3(1.2, 0.0, 0.2))
	await frame()
	var seated: bool = game.actors.enter()
	check(seated or game.driving, "the player is seated in the van for the %s drive" % district)
	if not game.driving:
		Fixture.driving(game, true)
		game.actors.sync()
	await frame()
	await frame()
	var route: Dictionary = game.routes.route()
	var data := {
		"district": district, "address": address_id, "ok": false, "measured": -1.0,
		"estimate": float(game.routes.guidance().get("eta_seconds", INF)),
		"drive_seconds": float(route.get("drive_seconds", INF)),
	}
	check(str(route.get("address_id", "")) == address_id and bool(route.get("reachable", false)),
		"the running game plans the legal route to %s (%s)" % [address_id, district])
	if not bool(route.get("reachable", false)):
		return data
	var points: Array = route.drive_points
	check(points.size() >= 2, "the %s leg arrives with a drivable polyline" % district)
	var park_point: Vector3 = route.park_position
	var before := hints.size()
	var clock_before := float(game.orders.remaining)
	var start := Engine.get_physics_frames()
	var completed := true
	for index in points.size():
		var reached := await steer_to(points[index])
		if reached < 0.0:
			completed = false
			print("PHASE 11 ROUTE: stalled in %s at waypoint %d/%d target=%s actual=%s speed=%.2f" % [
				district, index, points.size(), str(points[index]),
				str(game.van.global_position), game.van.speed])
			break
	var measured := _sim_seconds(start)
	var clock_used := clock_before - float(game.orders.remaining)
	var estimate := float(route.drive_seconds)
	data["measured"] = measured
	data["ok"] = completed
	check(completed, "the van drives the whole %s leg with ordinary input" % district)
	check(completed and absf(measured - clock_used) < 3.0,
		"the measured %s drive agrees with the game's own deadline clock (%.1fs vs %.1fs)" % [
			district, measured, clock_used])
	check(game.van.global_position.distance_to(park_point) < 7.0,
		"the %s drive ends on the authored parking pad" % district)
	check(absf(game.van.global_position.y) < 0.35, "the %s drive keeps the van on the ground" % district)
	# The measured-vs-estimated record: the conservative speed must never promise
	# less time than a careful real drive took, beyond the time a standing start
	# and hand steering cost. `drive_seconds` assumes the cap speed from the first
	# metre; a real pull-away spends `cap / ACCEL` seconds getting there.
	var cap: float = float(game.balance.conservative_route_speed)
	var pull_away: float = cap * cap / (2.0 * float(game.van.ACCEL))
	check(completed and measured <= estimate + pull_away + 1.0,
		"the conservative estimate covers the measured %s drive (measured %.1fs, estimate %.1fs)" % [
			district, measured, estimate])
	check(measured > 6.0, "the %s drive is long enough to measure meaningfully" % district)
	check(measured <= float(data.estimate),
		"the published %s ETA covers the measured drive including its allowances" % district)
	check(measured / maxf(estimate, 0.01) > 0.5,
		"the conservative speed is not more than twice as slow as a safe drive in %s" % district)
	check(hints.size() > before, "live guidance speaks while driving through %s" % district)
	var saw_park := false
	for hint in hints:
		if hint.begins_with("PARK"):
			saw_park = true
	check(saw_park, "guidance announces the parking pad before the %s stop" % district)
	release_all()
	# Parked, exited and walked: the last stretch is covered on foot with ordinary
	# movement input, so "the route ends at the customer's door" is measured here
	# instead of taken from the plan.
	var stopped := await brake_to_stop()
	check(stopped, "the van stops on the %s parking pad before the driver steps out" % district)
	var left: bool = game.actors.exit()
	check(left or not game.driving, "the driver leaves the van beside the %s pad" % district)
	if not left or game.driving:
		release_all()
		return data
	await frame()
	var walk_points: Array = route.walk_points
	check(walk_points.size() >= 2, "the %s walk leg arrives with a pedestrian polyline" % district)
	var walk_hints := hints.size()
	walk_spoke = false
	var walked := await walk_to_door(route)
	var door: Vector3 = route.door_position
	check(walked and game.pip.global_position.distance_to(door) < 1.6,
		"Pip walks from the parked van to the %s door with ordinary input (%.1f m from the door)" % [
			district, game.pip.global_position.distance_to(door)])
	check(absf(game.pip.global_position.y) < 0.35,
		"the %s walk-up keeps Pip on the ground" % district)
	var door_hint := str(game.routes.guidance().get("hint", ""))
	check(door_hint.begins_with("DOOR"),
		"the %s walk ends on the door hint (got \"%s\")" % [district, door_hint])
	check(walk_spoke or hints.size() > walk_hints,
		"live guidance stays alive while walking to the %s door" % district)
	data["door_gap"] = game.pip.global_position.distance_to(door)
	release_all()
	return data


## The longest legal drive inside a district: the representative case for the
## estimate, because short hops are never the risk.
func _longest_address(district: String) -> String:
	var spawn: Vector3 = game.world.van_spawn.global_position
	var best := ""
	var best_seconds := -1.0
	for address_id in game.world.graph.address_ids():
		if str(game.world.graph.address_data(address_id).get("district_id", "")) != district:
			continue
		var seconds := float(game.routes.estimate_from(spawn, address_id))
		if is_finite(seconds) and seconds > best_seconds:
			best_seconds = seconds
			best = address_id
	return best


func run() -> void:
	InputMap.load_from_project_settings()
	var game_scene: PackedScene = ResourceLoader.load(
		"res://scenes/game.tscn", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	game = game_scene.instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	check(game.world_ready, "the world binds for the measured drive")
	if not game.world_ready:
		print("PHASE 11 ROUTE: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	Engine.time_scale = 2.0
	game.camera.reduced_motion = true
	var districts: Array[String] = []
	for row in game.world.graph.layout.get("districts", []):
		districts.append(str(row.get("id", "")))
	check(districts.size() >= 5, "the catalog exposes five districts to drive through")
	var rows: Array = []
	for district in districts:
		var address_id := _longest_address(district)
		check(address_id != "", "district %s has an address to measure" % district)
		if address_id == "":
			continue
		rows.append(await measure(address_id, district))
	release_all()
	var cap: float = float(game.balance.conservative_route_speed)
	var pull_away: float = cap * cap / (2.0 * float(game.van.ACCEL))
	print("PHASE 11 MEASURED DRIVE (real input, throttle capped at %.1f m/s):" % cap)
	var worst_late := -INF
	for row in rows:
		var ratio := float(row.measured) / maxf(float(row.drive_seconds), 0.01)
		worst_late = maxf(worst_late, float(row.measured) - float(row.drive_seconds))
		print("  %-12s %-20s drive_estimate=%6.1fs measured=%6.1fs ratio=%.2f eta=%6.1fs walk_gap=%.1fm ok=%s" % [
			row.district, row.address, float(row.drive_seconds), float(row.measured),
			ratio, float(row.estimate), float(row.get("door_gap", INF)), str(row.ok)])
	check(rows.size() == districts.size(), "every district produced a measured drive")
	check(worst_late <= pull_away + 1.0,
		"no measured drive outran its conservative estimate (worst %.2fs over, pull-away allowance %.2fs)" % [
			worst_late, pull_away])
	Engine.time_scale = 1.0
	if game:
		Fixture.cleanup(game)
		game.queue_free()
		game = null
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	print("PHASE 11 ROUTE: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _initialize() -> void:
	call_deferred("run")
