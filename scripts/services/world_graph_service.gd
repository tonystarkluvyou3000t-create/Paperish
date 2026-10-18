extends RefCounted
## Data-backed street and pedestrian routes. Distances are metres; travel costs are seconds.

const DEFAULT_LAYOUT := "res://data/world/world_layout.json"
var layout: Dictionary = {}
var addresses: Dictionary = {}
var road_nodes: Dictionary = {}
var pedestrian_nodes: Dictionary = {}
var road_adjacency: Dictionary = {}
var pedestrian_adjacency: Dictionary = {}
var load_error := ""


func load_layout(path: String = DEFAULT_LAYOUT) -> bool:
	load_error = ""
	if not FileAccess.file_exists(path):
		load_error = "world layout missing: " + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_error = "world layout must be a JSON object"
		return false
	layout = parsed
	addresses.clear()
	road_nodes.clear()
	pedestrian_nodes.clear()
	road_adjacency.clear()
	pedestrian_adjacency.clear()
	for row in layout.get("addresses", []):
		if not row is Dictionary or not row.get("id", "") is String or str(row.id).is_empty():
			load_error = "address record requires a stable string ID"
			return false
		if addresses.has(row.id):
			load_error = "duplicate address ID: " + str(row.id)
			return false
		addresses[row.id] = row
	for node in layout.get("road_graph", {}).get("nodes", []): road_nodes[node.id] = node
	for node in layout.get("pedestrian_graph", {}).get("nodes", []): pedestrian_nodes[node.id] = node
	for lane in layout.get("road_graph", {}).get("lanes", []):
		var road_from := str(lane.get("from", ""))
		if not road_adjacency.has(road_from): road_adjacency[road_from] = []
		road_adjacency[road_from].append(lane)
	for link in layout.get("pedestrian_graph", {}).get("edges", []):
		var pedestrian_from := str(link.get("from", ""))
		if not pedestrian_adjacency.has(pedestrian_from): pedestrian_adjacency[pedestrian_from] = []
		pedestrian_adjacency[pedestrian_from].append(link)
	for row in addresses.values():
		if not road_nodes.has(row.get("road_node_id", "")):
			load_error = "address has no road node: " + str(row.id)
			return false
	return true


func address_data(address_id: String) -> Dictionary:
	return addresses.get(address_id, {})


func nearest_legal_entry(position: Vector3, vehicle_type: String = "delivery_van") -> Dictionary:
	var best := {"reachable": false, "distance_m": INF}
	var p := Vector2(position.x, position.z)
	for lane in layout.get("road_graph", {}).get("lanes", []):
		if lane.get("vehicle_type", "") != vehicle_type:
			continue
		var a: Dictionary = road_nodes.get(lane.get("from", ""), {})
		var b: Dictionary = road_nodes.get(lane.get("to", ""), {})
		if a.is_empty() or b.is_empty(): continue
		var av := Vector2(float(a.position[0]), float(a.position[1]))
		var bv := Vector2(float(b.position[0]), float(b.position[1]))
		var delta := bv - av
		var t := clampf((p - av).dot(delta) / maxf(delta.length_squared(), 0.0001), 0.0, 1.0)
		var projection := av + delta * t
		var distance := p.distance_to(projection)
		if distance < float(best.distance_m):
			best = {"reachable": true, "lane_id": lane.id, "node_id": lane.to,
				"from_node_id": lane.from, "position": Vector3(projection.x, 0.0, projection.y),
				"distance_m": distance + (1.0 - t) * float(lane.length_m),
				"projection_distance_m": distance, "remaining_lane_m": (1.0 - t) * float(lane.length_m)}
	return best


func vehicle_route(position: Vector3, address_id: String, closed_lanes: Array[String] = []) -> Dictionary:
	var address := address_data(address_id)
	if address.is_empty(): return _unreachable("unknown address: " + address_id)
	var entry := nearest_legal_entry(position)
	if not bool(entry.get("reachable", false)): return _unreachable("no legal vehicle lane near start")
	var target := str(address.get("road_node_id", ""))
	var path := _shortest_path("road_graph", str(entry.node_id), target, closed_lanes, "delivery_van")
	if not bool(path.get("reachable", false)):
		return _unreachable("road graph disconnected from " + address_id)
	var approach_m := float(entry.get("distance_m", INF))
	var access_m := float(address.get("road_connector_m", 0.0))
	var road_m := approach_m + float(path.distance_m) + access_m
	var ped := pedestrian_route(str(address.get("ped_park_id", "")), str(address.get("ped_door_id", "")))
	if not bool(ped.get("reachable", false)):
		return _unreachable("pedestrian graph cannot reach door for " + address_id)
	return {"reachable": true, "address_id": address_id, "road_distance_m": road_m,
		"drive_distance_m": approach_m + float(path.distance_m), "parking_approach_m": access_m,
		"walk_distance_m": float(ped.distance_m), "road_path": path.path,
		"nearest_entry": entry, "parking_node_id": target}


func pedestrian_route(from_id: String, to_id: String, blocked_edges: Array[String] = []) -> Dictionary:
	return _shortest_path("pedestrian_graph", from_id, to_id, blocked_edges, "pedestrian")


func route_seconds(route: Dictionary, road_speed_mps: float, parking_seconds: float) -> float:
	if not bool(route.get("reachable", false)): return INF
	return float(route.road_distance_m) / maxf(road_speed_mps, 0.1) + float(route.walk_distance_m) / 1.35 + parking_seconds


func _shortest_path(graph_name: String, start: String, target: String, closed: Array[String], mode: String) -> Dictionary:
	var nodes: Dictionary = road_nodes if graph_name == "road_graph" else pedestrian_nodes
	if not nodes.has(start) or not nodes.has(target): return _unreachable("unknown graph node")
	if start == target: return {"reachable": true, "distance_m": 0.0, "path": [start]}
	var distances := {start: 0.0}
	var previous: Dictionary = {}
	var visited: Dictionary = {}
	var adjacency: Dictionary = road_adjacency if graph_name == "road_graph" else pedestrian_adjacency
	while true:
		var current := ""
		var current_cost := INF
		for key in distances:
			if visited.has(key): continue
			if float(distances[key]) < current_cost:
				current = str(key)
				current_cost = float(distances[key])
		if current.is_empty(): break
		if current == target: break
		visited[current] = true
		for edge in adjacency.get(current, []):
			if closed.has(str(edge.get("id", ""))): continue
			if graph_name == "road_graph" and str(edge.get("vehicle_type", "")) != mode: continue
			var next := str(edge.get("to", ""))
			var cost := current_cost + float(edge.get("length_m", INF))
			if cost < float(distances.get(next, INF)):
				distances[next] = cost
				previous[next] = current
	if not distances.has(target): return _unreachable("no graph path")
	var path := [target]
	var cursor := target
	while cursor != start:
		cursor = str(previous.get(cursor, ""))
		if cursor.is_empty(): return _unreachable("broken predecessor chain")
		path.push_front(cursor)
	return {"reachable": true, "distance_m": float(distances[target]), "path": path}


func _unreachable(reason: String) -> Dictionary:
	return {"reachable": false, "distance_m": INF, "road_distance_m": INF,
		"walk_distance_m": INF, "travel_seconds": INF, "reason": reason, "path": []}
