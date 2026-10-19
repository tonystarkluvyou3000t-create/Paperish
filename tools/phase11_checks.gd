extends SceneTree
## Phase 11 checks: route service, guidance, map modal, stop planning and the
## unstuck policy. Catalog/service checks run against the authored layout;
## integration checks run against the real game scene - never a mock.

const GraphService = preload("res://scripts/services/world_graph_service.gd")
const RouteService = preload("res://scripts/services/route_service.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const Fixture = preload("res://tools/dev_fixture.gd")

var checks := 0
var failures: Array[String] = []
var graph
var balance
var routes
var game: Node
var _water: Array = []
var _buildings: Array = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures.append(message)
		printerr("FAIL ", message)


func frame() -> void:
	await process_frame


# ------------------------------------------------------------------ geometry


func water_rects() -> Array:
	var rects: Array = []
	for row in graph.water_surfaces():
		rects.append([float(row.rect[0]), float(row.rect[1]), float(row.rect[2]), float(row.rect[3])])
	return rects


func inside_water(point: Vector3, rects: Array) -> bool:
	for rect in rects:
		if point.x >= rect[0] + 0.05 and point.x <= rect[1] - 0.05 \
			and point.z >= rect[2] + 0.05 and point.z <= rect[3] - 0.05:
			return true
	return false


func segment_crosses_water(a: Vector3, b: Vector3, rects: Array) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 4.0)))
	for index in range(steps + 1):
		if inside_water(a.lerp(b, float(index) / float(steps)), rects):
			return true
	return false


func building_rects() -> Array:
	var rects: Array = []
	for row in graph.layout.get("addresses", []):
		var position: Array = row.position
		var size: Array = row.footprint_m
		var front := 1.0 if bool(row.get("north", true)) else -1.0
		var cx := float(position[0])
		var cz := float(position[1]) - front * float(size[1]) / 2.0
		rects.append({"id": str(row.id), "x0": cx - float(size[0]) / 2.0 + 0.05,
			"x1": cx + float(size[0]) / 2.0 - 0.05,
			"z0": cz - float(size[1]) / 2.0 + 0.05, "z1": cz + float(size[1]) / 2.0 - 0.05})
	return rects


func inside_building(point: Vector3) -> bool:
	for rect in _buildings:
		if point.x > rect.x0 and point.x < rect.x1 and point.z > rect.z0 and point.z < rect.z1:
			return true
	return false


func segment_enters_building(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(2, int(ceil(a.distance_to(b) / 1.0)))
	for index in range(steps + 1):
		if inside_building(a.lerp(b, float(index) / float(steps))):
			return true
	return false


func chain_points(points: Array) -> Array:
	return points


func drive_leg_ok(route: Dictionary, address_id: String) -> String:
	var points: Array = route.get("drive_points", [])
	var path: Array = route.get("road_path", [])
	# points[0] is the projection on the entry lane, then one point per node and
	# the parking marker as the roll-in.
	if points.size() != path.size() + 2:
		return address_id + ": drive polyline does not match the road path"
	for index in range(1, path.size() + 1):
		if points[index].distance_to(graph.road_node_position(str(path[index - 1]))) > 0.6:
			return address_id + ": drive segment %d does not join the road node" % index
	if points[points.size() - 1].distance_to(route.park_position) > 0.05:
		return address_id + ": drive leg does not end at the parking marker"
	for index in range(path.size() - 1):
		if graph.lane_between(str(path[index]), str(path[index + 1])).is_empty():
			return address_id + ": path uses a non-directed or missing lane %s -> %s" % [path[index], path[index + 1]]
	return ""


func walk_leg_ok(route: Dictionary, address_id: String) -> String:
	var points: Array = route.get("walk_points", [])
	if points.is_empty() or points[points.size() - 1].distance_to(route.door_position) > 0.05:
		return address_id + ": walk leg does not end at the door threshold"
	return ""


# -------------------------------------------------------------- service checks


func service_checks() -> void:
	# Catalog water: the map layer and the physics plates share one source.
	var water: Array = graph.water_surfaces()
	check(water.size() >= 6, "catalog authors the ocean, harbor and pond water record(s)")
	var water_ok := true
	for row in water:
		var rect: Array = row.get("rect", [])
		if rect.size() != 4 or not (float(rect[0]) < float(rect[1]) and float(rect[2]) < float(rect[3])):
			water_ok = false
	check(water_ok, "every water rect is a valid plan rectangle")
	var kinds: Array[String] = []
	for row in water: kinds.append(str(row.kind))
	check(kinds.has("pond") and kinds.has("harbor") and kinds.count("ocean") >= 4,
		"pond, harbor and four ocean plates are authored")
	check(graph.lane_between(str(graph.layout.road_graph.nodes[0].id), "nope").is_empty(),
		"lane_between rejects unknown connections")
	var probe = graph.road_node_position(str(graph.layout.road_graph.nodes[0].id))
	var node_row: Array = graph.layout.road_graph.nodes[0].position
	check(probe.distance_to(Vector3(float(node_row[0]), 0.0, float(node_row[1]))) < 0.001,
		"road_node_position matches the catalog node")
	var sidewalk = graph.pedestrian_nearest_node(Vector3(0.0, 0.0, 3.4))
	check(bool(sidewalk.get("reachable", false)) and float(sidewalk.distance_m) < 3.0,
		"pedestrian_nearest_node snaps a roadside position to a walk node")

	# Every authored address must plan a legal, directed route from the shop.
	var start: Array = graph.layout.get("routing", {}).get("shop_start_position", [0.0, 8.28])
	var shop_start = Vector3(float(start[0]), 0.0, float(start[1]))
	var shop_van := Vector3(0.0, 0.0, 1.85)
	var reachable := 0
	var drive_problem := ""
	var walk_problem := ""
	var water_problem := ""
	var building_problem := ""
	var directed_problem := ""
	var order_problem := ""
	var eta_problem := ""
	for address_id in graph.address_ids():
		var route = routes.plan(address_id, shop_van, shop_van, true)
		if not bool(route.get("reachable", false)):
			if drive_problem.is_empty():
				drive_problem = address_id + ": " + str(route.get("reason", "unreachable"))
			continue
		reachable += 1
		if str(route.address_id) != address_id:
			order_problem = address_id + ": plan resolved a different address"
		var drive_check := drive_leg_ok(route, address_id)
		if not drive_check.is_empty() and drive_problem.is_empty(): drive_problem = drive_check
		var walk_check := walk_leg_ok(route, address_id)
		if not walk_check.is_empty() and walk_problem.is_empty(): walk_problem = walk_check
		var segments: Array = route.get("segments", [])
		var cursor := Vector3(route.drive_points[0]) if not route.drive_points.is_empty() else Vector3.ZERO
		for segment in segments:
			if segment["from"].distance_to(cursor) > 0.05 and str(segment.kind) == "drive":
				order_problem = address_id + ": route segments are not contiguous"
			cursor = segment["to"]
		var points: Array = route.get("points", [])
		for index in range(points.size() - 1):
			if segment_crosses_water(points[index], points[index + 1], _water):
				water_problem = address_id + ": route crosses water at index %d" % index
				break
		var walk_points: Array = route.get("walk_points", [])
		for index in range(walk_points.size() - 1):
			if segment_enters_building(walk_points[index], walk_points[index + 1]):
				building_problem = address_id + ": walk leg enters a building"
				break
		for index in range(route.drive_points.size() - 1):
			if segment_enters_building(route.drive_points[index], route.drive_points[index + 1]):
				building_problem = address_id + ": drive leg enters a building"
				break
		# ETA is the conservative sum of its named parts: no hidden rounding.
		var expected := float(route.drive_seconds) + float(route.walk_seconds) \
			+ float(route.parking_seconds) + float(route.allowance_seconds)
		if absf(float(route.eta_seconds) - expected) > 0.02:
			eta_problem = address_id + ": eta does not equal drive + walk + allowances"
		if str(route.get("code", "")) != "ok":
			directed_problem = address_id + ": reachable route kept a failure code"
	check(drive_problem.is_empty(), "every address plans a legal directed drive leg (%s)" % (drive_problem if not drive_problem.is_empty() else "44/44"))
	check(walk_problem.is_empty(), "every address plans a walk leg ending at its door (%s)" % (walk_problem if not walk_problem.is_empty() else "44/44"))
	check(reachable == graph.address_ids().size(), "all %d addresses are reachable from the shop" % graph.address_ids().size())
	check(water_problem.is_empty(), "no planned route crosses authored water (%s)" % (water_problem if not water_problem.is_empty() else "clean"))
	check(building_problem.is_empty(), "no planned route crosses a building footprint (%s)" % (building_problem if not building_problem.is_empty() else "clean"))
	check(order_problem.is_empty(), "route segments stay ordered and address-faithful (%s)" % (order_problem if not order_problem.is_empty() else "clean"))
	check(eta_problem.is_empty(), "the estimate is exactly drive + walk + parking/exit/handoff allowances")

	# Existing per-leg geometry: a district sample in both directions.
	for district_id in ["downtown", "residential", "waterfront", "hillside", "market"]:
		var sample := ""
		for address_id in graph.address_ids():
			if str(graph.address_data(address_id).district_id) == district_id:
				sample = address_id
				break
		var route = routes.plan(sample, shop_van, shop_van, true)
		check(bool(route.get("reachable", false))
			and drive_leg_ok(route, sample).is_empty() and walk_leg_ok(route, sample).is_empty(),
			"district %s samples a directed drive leg and a door-accurate walk leg" % district_id)

	# The van driveway walk node is a leaf: Pip standing beside the parked van
	# must still get a route to any house door, starting where he stands.
	var leaf_pip := shop_van + Vector3(1.2, 0.0, 0.2)
	var leaf_route = routes.plan("2 Marinara Way", shop_van, leaf_pip, false)
	check(bool(leaf_route.get("reachable", false)) and walk_leg_ok(leaf_route, "2 Marinara Way").is_empty(),
		"a route is still reachable on foot from the van driveway leaf node")
	var leaf_points: Array = leaf_route.get("walk_points", [])
	check(not leaf_points.is_empty()
		and Vector3(leaf_points[0]).distance_to(Vector3(leaf_pip.x, 0.0, leaf_pip.z)) < 0.05,
		"the rescued walk leg still starts where the walker stands")
	check(routes.plan("2 Marinara Way", shop_van, leaf_pip, true).get("reachable", false),
		"the same driveway position keeps its normal drive-leg route")

	# Closure handling: one blocked lane either reroutes legally or reports a state.
	var target := "2 Marinara Way"
	var base = routes.plan(target, shop_van, shop_van, true)
	check(bool(base.get("reachable", false)), "closure probe starts from a reachable downtown route")
	var path: Array = base.road_path
	var blocked_lane := ""
	for index in range(path.size() - 1):
		var lane: Dictionary = graph.lane_between(str(path[index]), str(path[index + 1]))
		if not lane.is_empty():
			blocked_lane = str(lane.id)
			break
	routes.set_closures([blocked_lane])
	var rerouted = routes.plan(target, shop_van, shop_van, true)
	var reroute_ok := false
	if bool(rerouted.get("reachable", false)):
		reroute_ok = true
		var reroute_path: Array = rerouted.road_path
		for index in range(reroute_path.size() - 1):
			var lane: Dictionary = graph.lane_between(str(reroute_path[index]), str(reroute_path[index + 1]))
			if str(lane.get("id", "")) == blocked_lane:
				reroute_ok = false
		reroute_ok = reroute_ok and float(rerouted.drive_distance_m) >= float(base.drive_distance_m) - 0.01
	else:
		reroute_ok = str(rerouted.get("code", "")) == "unreachable" and str(rerouted.get("reason", "")) != ""
	check(reroute_ok, "a closed lane either reroutes legally or reports an explicit unreachable state")
	check(str(rerouted.address_id) == target, "a closed lane never silently swaps the customer")

	var address: Dictionary = graph.address_data(target)
	var target_node := str(address.get("road_node_id", ""))
	var blocked: Array[String] = []
	for lane in graph.layout.road_graph.lanes:
		if str(lane.to) == target_node:
			blocked.append(str(lane.id))
	routes.set_closures(blocked)
	var cut = routes.plan(target, shop_van, shop_van, true)
	check(not bool(cut.get("reachable", false)) and cut.segments.is_empty()
		and str(cut.get("code", "")) == "unreachable" and str(cut.get("reason", "")) != ""
		and not is_finite(float(cut.get("eta_seconds", 0.0))),
		"cutting every lane into the destination reports unreachable with a reason and no segments")
	check(str(cut.address_id) == target, "the unreachable report keeps the requested address")
	routes.set_closures([])

	# Recompute policy: never per frame, always on deviation or topology change.
	routes.set_target("")
	routes.update(0.016, true, shop_van, shop_van)
	routes.set_target(target)
	var planned = routes.recomputes
	routes.update(0.016, true, shop_van, shop_van)
	check(routes.recomputes == planned + 1 and routes.last_reason == "target",
		"the first update after a target change plans exactly once")
	var before = routes.recomputes
	for _i in range(180):
		routes.update(0.016, true, shop_van, shop_van)
	check(routes.recomputes == before, "standing still inside the route never recomputes per frame")
	routes.update(0.016, true, Vector3(120.0, 0.0, -80.0), Vector3(120.0, 0.0, -80.0))
	check(routes.recomputes > before and routes.last_reason == "deviation",
		"a meaningful deviation recomputes the route")
	before = routes.recomputes
	routes.set_closures([blocked_lane])
	routes.update(0.016, true, Vector3(120.0, 0.0, -80.0), Vector3(120.0, 0.0, -80.0))
	check(routes.recomputes > before and routes.last_reason == "closures",
		"a topology change recomputes the route")
	routes.set_closures([])

	# Guidance text follows the leg and the door, not the house centre.
	var guided = routes.plan(target, shop_van, shop_van, true)
	routes.set_target(target)
	routes.update(0.016, true, shop_van, shop_van)
	var hint_a := str(routes.guidance().get("hint", ""))
	check(not hint_a.is_empty() and str(routes.guidance().leg) == "drive",
		"driving guidance starts on the drive leg with a spoken hint")
	var park: Vector3 = guided.park_position
	routes.update(0.016, true, park, park)
	check(str(routes.guidance().get("hint", "")).begins_with("PARK"),
		"arriving at the parking spot switches the hint to PARK")
	var door: Vector3 = guided.door_position
	routes.update(0.016, false, park, door)
	check(str(routes.guidance().leg) == "walk" and str(routes.guidance().hint).begins_with("DOOR"),
		"on foot at the door the hint points at the door itself")
	var hints := {}
	for point in guided.drive_points:
		routes.update(0.016, true, point, point)
		hints[str(routes.guidance().get("hint", ""))] = true
	check(hints.size() >= 2, "the drive leg produces turn guidance that changes along the route")

	# Stop planning: the player's order is preserved, never optimised away.
	var ids = graph.address_ids()
	routes.set_stops([{"order_id": 1, "address_id": ids[0]}, {"order_id": 2, "address_id": ids[1]},
		{"order_id": 3, "address_id": ids[2]}])
	var plan = routes.stops()
	check(plan.size() == 3 and int(plan[0].order_id) == 1 and int(plan[2].order_id) == 3,
		"three tickets keep the order they were added in")
	check(routes.move_stop(3, -1) and int(routes.stops()[1].order_id) == 3,
		"the player can move a stop up the list")
	var rows = routes.stop_estimates(shop_van, {1: 500.0, 2: 500.0, 3: 500.0})
	check(rows.size() == 3 and bool(rows[0].reachable) and float(rows[1].cumulative_seconds) >= float(rows[0].cumulative_seconds)
		and float(rows[2].cumulative_seconds) >= float(rows[1].cumulative_seconds),
		"stop rows compare cumulative arrival estimates in plan order")
	check(float(rows[0].slack_seconds) > 0.0, "a generous window reports positive slack")
	var tight = routes.stop_estimates(shop_van, {1: 1.0, 2: 500.0, 3: 500.0})
	check(float(tight[0].slack_seconds) < 0.0, "a tight window reports negative slack for comparison")
	routes.set_stops([{"order_id": 1, "address_id": ids[0]}, {"order_id": 3, "address_id": ids[2]},
		{"order_id": 2, "address_id": ids[1]}])
	check(int(routes.stops()[0].order_id) == 1 and int(routes.stops()[1].order_id) == 3
		and int(routes.stops()[2].order_id) == 2,
		"a new ticket appends without re-sorting the player's plan")
	routes.set_stops([{"order_id": 1, "address_id": ids[0]}, {"order_id": 3, "address_id": ids[2]}])
	check(routes.stops().size() == 2 and int(routes.stops()[1].order_id) == 3,
		"closing a ticket prunes it while the rest keeps its order")
	routes.set_stops([])

	# Waypoints are explicit, optional and clearable.
	check(not routes.has_waypoint(), "no waypoint is set by default")
	routes.set_waypoint(Vector2(-28.0, -6.0))
	check(routes.has_waypoint() and routes.waypoint().distance_to(Vector2(-28.0, -6.0)) < 0.01,
		"a player waypoint round-trips")
	routes.clear_waypoint()
	check(not routes.has_waypoint(), "the waypoint can be cleared")

	# Unknown targets are explicit, never a silent substitution.
	var unknown = routes.plan("no such address", shop_van, shop_van, true)
	check(not bool(unknown.get("reachable", false)) and str(unknown.get("code", "")) == "unknown_address"
		and unknown.segments.is_empty() and str(unknown.address_id) == "no such address",
		"an unknown address reports an explicit unknown-address state")


# ------------------------------------------------------------ scene integration


func scene_checks() -> void:
	InputMap.load_from_project_settings()
	check(InputMap.has_action("map"), "the map action exists in the input map")
	var scene: PackedScene = ResourceLoader.load("res://scenes/game.tscn", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	check(game.world_ready, "the game scene binds the world for navigation checks")

	var ids: Array[String] = game.destination_ids()
	var far_id := ""
	for address_id in ids:
		if str(game.world.graph.address_data(address_id).district_id) == "residential":
			far_id = address_id
			break
	game.force_destination(far_id)
	game.orders.deliveries = 8
	check(game.start_shift(), "a timed shift starts")
	await frame()
	check(game.routes.target().is_empty(), "no route is planned while the ticket is still at the counter")

	# Budget: the deadline covers the estimate plus minimum slack (long routes)
	# while short hops keep the classic pacing.
	var shop_start = game.world.shop_entrance.global_position
	var estimate = game.routes.estimate_from(shop_start, far_id)
	var base_deadline := maxf(game.balance.deadline_floor,
		game.balance.deadline_start - 8.0 * game.balance.deadline_decrease)
	var expected_deadline := maxf(base_deadline, estimate + float(game.balance.deadline_min_slack))
	check(absf(float(game.timer_max) - expected_deadline) < 0.05,
		"the ticket budget equals the conservative estimate plus minimum slack")
	check(expected_deadline > base_deadline,
		"a long route stretches its budget beyond the classic deadline")
	game.orders.deliveries = 0

	game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())
	check(game.orders.can_pickup(), "the ticket reaches the counter ready to collect")
	check(game.orders.pickup(), "the pizzas are physically collected at the counter")
	await frame()
	await frame()
	check(game.routes.target() == far_id, "the selected delivery becomes the route target")
	check(bool(game.routes.guidance().get("reachable", false)) and not str(game.routes.guidance().hint).is_empty(),
		"live guidance is reachable and readable after pickup")
	var snapshot = game.get_snapshot()
	check(snapshot.nav_mode == "map", "the navigation display defaults to the map mode")
	check(snapshot.route_points.size() > 2, "the snapshot carries the route polyline for the HUD map")

	# The setting switches the live card in a running game: minimap, compass only,
	# or gone. The session override is never persisted.
	var nav_card: Control = game.hud.get("_nav_card")
	var nav_map: Control = game.hud.get("_nav_map")
	game.settings.set_value("hud/navigation", "compass", false)
	await frame()
	check(nav_card != null and nav_card.visible and not nav_map.visible,
		"compass mode keeps the navigation card without the minimap")
	game.settings.set_value("hud/navigation", "off", false)
	await frame()
	check(nav_card != null and not nav_card.visible,
		"off mode hides the navigation card entirely")
	game.settings.set_value("hud/navigation", "map", false)
	await frame()
	check(nav_card != null and nav_card.visible and nav_map.visible,
		"map mode draws the minimap on the navigation card")

	# Guidance follows the legs in the running game: the drive leg parks at the
	# pad, then the same target guides the walk to the door.
	var route: Dictionary = game.routes.route()
	var drive_count := int(route.drive_end_index) + 1
	var park_point: Vector3 = route.park_position
	var door_point: Vector3 = route.door_position
	Fixture.driving(game, true)
	Fixture.place(game, "van", Vector3(park_point.x, 0.1, park_point.z))
	await frame()
	await frame()
	check(str(game.get_snapshot().nav_hint).begins_with("PARK"),
		"parking at the pad switches the live hint to PARK (got \"%s\")" % game.get_snapshot().nav_hint)
	Fixture.driving(game, false)
	Fixture.place(game, "pip", Vector3(door_point.x, 0.1, door_point.z))
	await frame()
	await frame()
	check(str(game.get_snapshot().nav_hint).begins_with("DOOR"), "walking to the door points at the entrance")
	Fixture.driving(game, true)

	# Map modal: pauses the simulation through the shared modal service.
	var opened = game.open_map()
	check(opened and game.map_open() and game.session.paused, "the town map opens as a shared modal pause")
	check(str(game.get_snapshot().menu_screen) == "map", "the map screen becomes the visible menu screen")
	check(paused, "the tree is paused while the map is open")
	check(not game.interact_available(), "gameplay interaction is not available behind the map")
	check(game.close_map() and not game.map_open() and not game.session.paused,
		"closing the map releases the pause reason")
	await frame()
	check(not paused, "the simulation resumes after the map closes")

	# Map opened from pause returns to pause, not to gameplay.
	game.session.toggle_pause()
	await frame()
	check(str(game.get_snapshot().menu_screen) == "pause", "pause opens its own screen")
	game.open_map()
	await frame()
	check(str(game.get_snapshot().menu_screen) == "map", "the map stacks above the pause menu")
	game.close_map()
	await frame()
	check(str(game.get_snapshot().menu_screen) == "pause", "closing the map returns to the pause menu")
	game.session.toggle_pause()
	await frame()

	# Stop plan in the running game: ordering, pruning and snapshot text.
	game.orders.queue_ticket(game.destination_ids(), false)
	game.orders.queue_ticket(game.destination_ids(), false)
	await frame()
	await frame()
	var planned_ids: Array = str(game.get_snapshot().plan_ids).split(",")
	var outstanding: Array = game.orders.outstanding_order_ids()
	check(planned_ids.size() == outstanding.size() and outstanding.size() >= 2
		and planned_ids[0] == str(game.orders.order_id),
		"the running plan lists every outstanding ticket with the selected one first")
	var other := int(planned_ids[1])
	check(game.routes.move_stop(other, -1), "a running plan stop moves up")
	check(str(game.get_snapshot().plan_ids).split(",")[0] == str(other),
		"the map's plan order reflects the player's own reordering")
	check(game.routes.move_stop(other, 1), "the stop moves back down")

	# UI alone: the map is opened from the pause screen and driven by its own
	# buttons - the same `pressed` signals a click or a controller emit.
	game.session.toggle_pause()
	await frame()
	check(game.menus.activate(&"map"), "the pause screen accepts the town map button")
	await frame()
	var screen: MapScreen = null
	for child in game.menus.get_children():
		if child is MapScreen:
			screen = child
	check(screen != null and str(game.get_snapshot().menu_screen) == "map",
		"the town map is the visible screen after that button")
	if screen != null:
		var row_ids := PackedStringArray()
		for card in _stop_cards(screen):
			row_ids.append(str(int(card.order_id)))
		var live_ids := PackedStringArray()
		for id in game.orders.outstanding_order_ids():
			live_ids.append(str(id))
		check(row_ids.size() == live_ids.size() and row_ids.size() >= 2,
			"the map lists every outstanding ticket as its own row (%s of %s), never re-sorted" % [
				",".join(row_ids), ",".join(live_ids)])
		var previous := int(game.orders.order_id)
		var picked := 0
		for card in _stop_cards(screen):
			if int(card.order_id) != previous:
				picked = int(card.order_id)
				break
		check(picked != 0 and _press_route(screen, picked) and int(game.orders.order_id) == picked,
			"pressing a row's ROUTE button selects that ticket (#%d)" % picked)
		await frame()
		# Selecting rebuilds the rows, so every press re-scans the live widgets.
		check(_press_route(screen, previous), "the collected ticket's row is still pressable (#%d)" % previous)
		await frame()
		check(int(game.orders.order_id) == previous
			and str(game.routes.target()) == game.orders.destination_id
			and not str(game.routes.target()).is_empty(),
			"the map's route selection is the ticket the van is driving to")
		var zoom_before: float = screen.map.metres_per_pixel
		_find_button(screen, "+ ZOOM").pressed.emit()
		await frame()
		check(screen.map.metres_per_pixel < zoom_before,
			"the map's + ZOOM button changes the shared renderer's scale")
		game.map_set_waypoint(Vector2(10.0, 10.0))
		await frame()
		check(game.routes.has_waypoint(), "a waypoint is set for the clear-button check")
		_find_button(screen, "CLEAR WAYPOINT").pressed.emit()
		await frame()
		check(not game.routes.has_waypoint(), "the map's clear button removes the waypoint")
		var timer_before := float(game.orders.remaining)
		_find_button(screen, "UNSTUCK").pressed.emit()
		await frame()
		check(float(game.orders.remaining) < timer_before,
			"the map's unstuck button charges the transparent policy time")
		# Controller selection: real gamepad events on the focused control. A saved
		# profile can shadow the shipped default, so the live binding is restored
		# from the project's own shipped events first (a fresh profile already has
		# it; the check proves the shipped default and the live path).
		var shipped_pad: InputEventJoypadButton = null
		var shipped: Dictionary = ProjectSettings.get_setting("input/confirm", {})
		for event in shipped.get("events", []):
			if event is InputEventJoypadButton:
				shipped_pad = event
		check(shipped_pad != null, "the shipped confirm binding carries a gamepad button")
		if shipped_pad != null and not InputMap.action_has_event(&"confirm", shipped_pad):
			var extra := InputEventJoypadButton.new()
			extra.button_index = shipped_pad.button_index
			extra.device = -1
			InputMap.action_add_event(&"confirm", extra)
		var pad_confirm := -1
		for event in InputMap.action_get_events("confirm"):
			if event is InputEventJoypadButton:
				pad_confirm = (event as InputEventJoypadButton).button_index
		check(pad_confirm >= 0, "the live confirm action carries the gamepad button")
		var route_button := _route_button(screen, picked)
		check(route_button != null, "the map row exposes a focusable ROUTE button")
		if route_button != null and pad_confirm >= 0:
			route_button.grab_focus()
			await frame()
			check(route_button.has_focus(), "a map row takes controller focus")
			var focused_before := screen.get_viewport().gui_get_focus_owner()
			await pad(JOY_BUTTON_DPAD_DOWN)
			check(screen.get_viewport().gui_get_focus_owner() != focused_before,
				"the d-pad moves map focus to another control")
			route_button.grab_focus()
			await frame()
			await pad(pad_confirm)
			check(int(game.orders.order_id) == picked,
				"the controller's confirm button selects the focused stop (#%d)" % picked)
			var back_button := _route_button(screen, previous)
			if back_button != null:
				back_button.grab_focus()
				await frame()
				await pad(pad_confirm)
				await frame()
			check(int(game.orders.order_id) == previous
				and str(game.routes.target()) == game.orders.destination_id,
				"the controller restores the routed ticket through the same map")
	game.menus.activate(&"back")
	await frame()
	check(str(game.get_snapshot().menu_screen) == "pause" and game.session.paused,
		"closing the town map lands back on the pause screen")
	game.session.toggle_pause()
	await frame()

	# Unstuck: a validated road anchor, transparent cost, cargo untouched.
	var anchors: Array = game.world.graph.layout.get("recovery_anchors", [])
	Fixture.place(game, "van", Vector3(58.0, 0.07, 12.0))
	game.van.rotation.y = 0.7
	Fixture.timer(game, 40.0)
	var cargo_before = int(game.get_snapshot().van_cargo_count)
	var money_before = game.money
	var deliveries_before = game.deliveries
	var strikes_before = game.strikes
	game.session.toggle_pause()
	check(game.unstuck(), "the pause unstuck action returns a legal position")
	var nearest := INF
	for anchor in anchors:
		nearest = minf(nearest, game.van.global_position.distance_to(
			Vector3(float(anchor.position[0]), game.van.global_position.y, float(anchor.position[1]))))
	check(nearest < 1.5, "the van lands on a validated recovery anchor")
	check(absf(game.timer - (40.0 - float(game.balance.unstuck_time_cost))) < 0.2,
		"the timed shift shows the transparent unstuck cost on the running clock")
	check(game.money == money_before and game.deliveries == deliveries_before
		and game.strikes == strikes_before and int(game.get_snapshot().van_cargo_count) == cargo_before,
		"unstuck never settles a delivery, pays out or drops cargo")
	game.session.toggle_pause()

	# The floor protects a nearly-expired order from being killed by the rescue:
	# the charge stops at the floor and never reaches zero.
	Fixture.timer(game, 5.0)
	Fixture.place(game, "van", Vector3(58.0, 0.07, 12.0))
	check(game.unstuck() and game.timer >= float(game.balance.unstuck_min_remaining) - 0.01
		and game.timer > 0.0 and game.timer <= 5.0,
		"the unstuck floor keeps a nearly-expired order above zero")

	# Free roam: the same rescue, no timer, no charge.
	game.restart()
	check(game.start_free_roam(), "free roam starts for the unstuck policy check")
	await frame()
	Fixture.place(game, "van", Vector3(120.0, 0.07, -60.0))
	check(game.unstuck() and game.free_roam(), "free roam unstuck works and stays clock-free")

	if game:
		Fixture.cleanup(game)
		game.queue_free()
		game = null
	current_scene = null


## The first button in the tree whose label starts with `text`.
func _find_button(root: Node, text: String) -> Button:
	if root is Button and str(root.text).begins_with(text):
		return root
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


## Every live stop card in the map screen as {order_id, button}: the check reads
## the real widget layout instead of a private field. Rows queued for deletion by
## a refresh are skipped so the returned buttons are always pressable.
func _stop_cards(screen: Node) -> Array:
	var cards: Array = []
	for node in screen.find_children("*", "Button", true, false):
		if str(node.text) != "ROUTE" or node.is_queued_for_deletion():
			continue
		var marker: Node = node.get_parent().get_parent().get_child(0).get_child(0)
		cards.append({"order_id": int(str(marker.text).trim_prefix("#")), "button": node})
	return cards


## Presses the ROUTE button of one ticket's row exactly like a click would.
func _press_route(screen: Node, order_id: int) -> bool:
	var button := _route_button(screen, order_id)
	if button == null:
		return false
	button.pressed.emit()
	return true


## The live ROUTE button of one ticket's row, or null.
func _route_button(screen: Node, order_id: int) -> Button:
	for card in _stop_cards(screen):
		if int(card.order_id) == order_id:
			return card.button
	return null


## Sends one real joypad button press and release: what a controller emits.
func pad(button: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		event.device = 0
		Input.parse_input_event(event)
		await frame()


func run() -> void:
	graph = GraphService.new()
	check(graph.load_layout(), "world layout loads for route checks: " + graph.load_error)
	balance = load("res://data/balance.tres")
	routes = RouteService.new()
	routes.configure(graph, balance)
	_water = water_rects()
	_buildings = building_rects()
	service_checks()
	await scene_checks()
	await frame
	await frame
	await create_timer(0.2).timeout
	print("PHASE 11 CHECKS: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _initialize() -> void:
	call_deferred("run")
