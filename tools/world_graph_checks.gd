extends SceneTree
## Graph routing and stable-ID acceptance checks for Phase 09 onward.

const GraphService = preload("res://scripts/services/world_graph_service.gd")
const WorldRegistry = preload("res://scripts/services/world_registry.gd")
var checks := 0
var failures := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("WORLD GRAPH FAIL: " + label)


func _initialize() -> void:
	var graph = GraphService.new()
	check(graph.load_layout(), "world layout loads: " + graph.load_error)
	var ids: Array = []
	for row in graph.layout.get("addresses", []): ids.append(str(row.id))
	check(ids.size() >= 40, "expanded catalog has 40+ addresses and retains original destinations")
	var start_values: Array = graph.layout.get("routing", {}).get("shop_start_position", [0.0, 8.28])
	var start := Vector3(float(start_values[0]), 0.1, float(start_values[1]))
	var entry := graph.nearest_legal_entry(start)
	check(bool(entry.get("reachable", false)), "nearest legal delivery-van lane resolves")
	for row in graph.layout.get("addresses", []):
		var route: Dictionary = graph.vehicle_route(start, str(row.id))
		check(bool(route.get("reachable", false)), "van route reaches " + str(row.id))
		check(is_finite(float(route.get("road_distance_m", INF))), "finite road route cost for " + str(row.id))
		check(float(route.get("walk_distance_m", INF)) >= 0.0, "connected parking-to-door path for " + str(row.id))
		var foot := graph.pedestrian_route("poi:pizza_pickup", str(row.ped_door_id))
		check(bool(foot.get("reachable", false)), "pedestrian network reaches " + str(row.id))
	var closed: Array[String] = []
	for lane in graph.layout.get("road_graph", {}).get("lanes", []): closed.append(str(lane.id))
	var blocked: Dictionary = graph.vehicle_route(start, str(ids[0]), closed)
	check(not bool(blocked.get("reachable", true)) and is_inf(float(blocked.get("road_distance_m", 0.0))),
		"closed road network returns explicit unreachable route")
	var unknown: Dictionary = graph.vehicle_route(start, "address:missing")
	check(not bool(unknown.get("reachable", true)), "unknown address returns explicit unreachable route")
	var registry = WorldRegistry.new()
	var changes: Array = []
	registry.registration_changed.connect(func(event: Dictionary) -> void: changes.append(event.duplicate()))
	var marker := Node3D.new()
	check(registry.register_marker("test:marker", "test", marker), "runtime marker registration")
	check(registry.marker("test:marker") == marker, "marker lookup resolves active node")
	registry.unregister_marker("test:marker")
	check(registry.marker("test:marker") == null, "unregistered marker no longer resolves")
	check(changes.size() == 2 and bool(changes[0].registered) and not bool(changes[1].registered),
		"registration changes emit immutable identity events")
	marker.free()
	var old_ids: Array = graph.layout.get("legacy_destination_order", [])
	check(old_ids.size() >= 8 and old_ids[0] == "2 Marinara Way" and old_ids[7] == "16 Marinara Way",
		"legacy destination ordering remains stable")
	print("PHASE 09 GRAPH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
