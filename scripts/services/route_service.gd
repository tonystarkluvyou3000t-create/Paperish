extends RefCounted
## Phase 11 Milestone A: directed, closure-aware delivery routes.
##
## A plan is ordered advice, never autopilot. The van leg follows directed lanes
## (including the player's current legal connection) and the walk leg follows the
## sidewalk/doorway graph to the customer's door. Routes recompute on meaningful
## deviation or topology change rather than every render frame, and an
## unreachable target is an explicit state - never a line through a building and
## never a silent swap to another customer.

signal route_changed(event: Dictionary)

const LEG_DRIVE := "drive"
const LEG_WALK := "walk"

var graph: RefCounted
var config: Resource
var recomputes := 0
var last_reason := ""

var _closed_lanes: Array[String] = []
var _closed_edges: Array[String] = []
var _route: Dictionary = {}
var _guidance: Dictionary = {}
var _target := ""
var _driving := false
var _dirty := true
var _dirty_reason := "topology"
var _cooldown := 0.0
var _stops: Array[Dictionary] = []
var _waypoint := Vector2(INF, INF)
var _van_position := Vector3.ZERO
var _actor_position := Vector3.ZERO


func configure(graph_service: RefCounted, balance: Resource) -> void:
	graph = graph_service
	config = balance


## Topology hooks for later phases (traffic, closures, events): the routes only
## change when the graph under them changes.
func set_closures(lanes: Array, edges: Array = []) -> bool:
	var next_lanes: Array[String] = []
	for lane in lanes: next_lanes.append(str(lane))
	var next_edges: Array[String] = []
	for edge in edges: next_edges.append(str(edge))
	if next_lanes == _closed_lanes and next_edges == _closed_edges:
		return false
	_closed_lanes = next_lanes
	_closed_edges = next_edges
	_dirty = true
	_dirty_reason = "closures"
	return true


func closures() -> Dictionary:
	return {"lanes": _closed_lanes.duplicate(), "edges": _closed_edges.duplicate()}


func invalidate(reason := "topology") -> void:
	last_reason = reason
	_dirty = true
	_dirty_reason = reason


func set_target(address_id: String) -> void:
	var next := address_id.strip_edges()
	if next == _target:
		return
	_target = next
	_dirty = true
	_dirty_reason = "target"


func target() -> String:
	return _target


func clear(reason := "cleared") -> void:
	_target = ""
	if _route.is_empty():
		_dirty = false
		return
	_route = {}
	_guidance = {}
	_dirty = false
	last_reason = reason
	route_changed.emit({"reason": reason, "reachable": false, "address_id": ""})


func route() -> Dictionary:
	return _route


func guidance() -> Dictionary:
	return _guidance


func update(delta: float, driving: bool, van_position: Vector3, actor_position: Vector3) -> void:
	_van_position = van_position
	_actor_position = actor_position
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _target.is_empty():
		if not _route.is_empty():
			_route = {}
			_guidance = {}
			route_changed.emit({"reason": "cleared", "reachable": false, "address_id": ""})
		return
	if _dirty:
		_recompute(driving, van_position, actor_position, _dirty_reason)
		return
	if driving != _driving:
		_recompute(driving, van_position, actor_position, "actor")
		return
	if _cooldown > 0.0:
		_refresh_guidance()
		return
	# Deviation is measured against the leg the actor is actually following.
	var points: Array = _route.get("drive_points", []) if driving else _route.get("walk_points", [])
	var limit := float(config.route_deviate_m) if driving else float(config.route_deviate_foot_m)
	if not points.is_empty() and float(_project(points, actor_position).offset_m) > limit:
		_recompute(driving, van_position, actor_position, "deviation")
	else:
		_refresh_guidance()


func plan(address_id: String, van_position: Vector3, actor_position: Vector3, driving: bool,
		reason := "plan") -> Dictionary:
	if graph == null or config == null:
		return _fail(address_id, "route service is not configured", "not_configured", reason, driving)
	var address: Dictionary = graph.address_data(address_id)
	if address.is_empty():
		return _fail(address_id, "no catalog entry for " + address_id, "unknown_address", reason, driving)
	var vehicle: Dictionary = graph.vehicle_route(van_position, address_id, _closed_lanes)
	if not bool(vehicle.get("reachable", false)):
		return _fail(address_id, str(vehicle.get("reason", "no legal vehicle route")), "unreachable", reason, driving)
	var drive := _drive_leg(address, vehicle)
	var walk := _walk_leg(address, actor_position, driving)
	if not bool(walk.get("reachable", false)):
		return _fail(address_id, str(walk.get("reason", "walk route blocked")), "unreachable", reason, driving)
	var door_point := Vector3(_pivot(address, "door_position").x, 0.0, _pivot(address, "door_position").y)
	var park_point := Vector3(_pivot(address, "park_position").x, 0.0, _pivot(address, "park_position").y)
	var drive_seconds := float(vehicle.get("road_distance_m", INF)) / maxf(float(config.conservative_route_speed), 0.1)
	var walk_seconds := float(vehicle.get("walk_distance_m", 0.0)) / maxf(float(config.route_walk_speed), 0.1)
	var allowance := float(config.route_exit_allowance) + float(config.route_handoff_allowance)
	var points: Array = drive.get("points", []).duplicate()
	points.append_array(walk.get("points", []).slice(1))
	_route = {
		"reachable": true, "address_id": address_id, "reason": "", "code": "ok",
		"label": str(address.get("address", address_id)), "district_id": str(address.get("district_id", "")),
		"closed_lanes": _closed_lanes.duplicate(),
		"segments": drive.get("segments", []) + walk.get("segments", []),
		"drive_segments": drive.get("segments", []), "walk_segments": walk.get("segments", []),
		"drive_points": drive.get("points", []), "walk_points": walk.get("points", []),
		"points": points, "drive_end_index": maxi(drive.get("points", []).size() - 1, 0),
		"maneuvers": drive.get("maneuvers", []) + walk.get("maneuvers", []),
		"drive_maneuvers": drive.get("maneuvers", []), "walk_maneuvers": walk.get("maneuvers", []),
		"road_path": vehicle.get("road_path", []).duplicate(),
		"drive_distance_m": float(vehicle.get("drive_distance_m", 0.0)),
		"parking_approach_m": float(vehicle.get("parking_approach_m", 0.0)),
		"walk_distance_m": float(vehicle.get("walk_distance_m", 0.0)),
		"walk_leg_distance_m": float(walk.get("distance_m", 0.0)),
		"drive_seconds": drive_seconds, "walk_seconds": walk_seconds,
		"parking_seconds": float(config.route_parking_allowance), "allowance_seconds": allowance,
		"eta_seconds": drive_seconds + walk_seconds + float(config.route_parking_allowance) + allowance,
		"park_position": park_point, "door_position": door_point,
	}
	_store(_route, driving, reason)
	return _route


## The same conservative estimate the ticket budget uses, from any position.
func estimate_from(position: Vector3, address_id: String) -> float:
	if graph == null or config == null:
		return INF
	return estimate_seconds(graph.vehicle_route(position, address_id, _closed_lanes))


## Drive + parking + walk + exit + handoff allowances. Preparation-independent,
## so a budget never assumes a zero-second hop-out or handoff.
func estimate_seconds(vehicle: Dictionary) -> float:
	if not bool(vehicle.get("reachable", false)):
		return INF
	var drive_seconds := float(vehicle.get("road_distance_m", INF)) / maxf(float(config.conservative_route_speed), 0.1)
	var walk_seconds := float(vehicle.get("walk_distance_m", 0.0)) / maxf(float(config.route_walk_speed), 0.1)
	return drive_seconds + walk_seconds + float(config.route_parking_allowance) \
		+ float(config.route_exit_allowance) + float(config.route_handoff_allowance)


# ------------------------------------------------------------------ stop planning


## Replace the visible stop list. Existing stops keep the player's order; new
## tickets append at the end. The service never re-sorts a player's plan.
func set_stops(stops: Array) -> void:
	var wanted := {}
	for stop in stops:
		var address_id := str(stop.get("address_id", ""))
		if address_id.is_empty():
			continue
		wanted[int(stop.get("order_id", 0))] = address_id
	var next: Array[Dictionary] = []
	for stop in _stops:
		var id := int(stop.order_id)
		if wanted.has(id):
			next.append({"order_id": id, "address_id": str(wanted[id])})
			wanted.erase(id)
	for id in wanted:
		next.append({"order_id": int(id), "address_id": str(wanted[id])})
	_stops = next


func stops() -> Array[Dictionary]:
	return _stops.duplicate()


func move_stop(order_id: int, delta: int) -> bool:
	for index in _stops.size():
		if int(_stops[index].order_id) != order_id:
			continue
		var target := clampi(index + delta, 0, _stops.size() - 1)
		if target == index:
			return false
		var stop := _stops[index]
		_stops.remove_at(index)
		_stops.insert(target, stop)
		return true
	return false


## Per-stop leg and cumulative estimates in the player's plan order, compared
## with whatever remaining delivery time the caller passes per order.
func stop_estimates(van_position: Vector3, remaining_by_id: Dictionary = {}) -> Array:
	var rows: Array = []
	if graph == null or config == null:
		return rows
	var cursor := van_position
	var cumulative := 0.0
	for stop in _stops:
		var address_id := str(stop.address_id)
		var vehicle: Dictionary = graph.vehicle_route(cursor, address_id, _closed_lanes)
		var order_id := int(stop.order_id)
		var row := {"order_id": order_id, "address_id": address_id,
			"reachable": bool(vehicle.get("reachable", false)),
			"reason": str(vehicle.get("reason", "")),
			"drive_distance_m": float(vehicle.get("drive_distance_m", INF)),
			"walk_distance_m": float(vehicle.get("walk_distance_m", INF)),
			"leg_seconds": INF, "cumulative_seconds": INF}
		if row.reachable:
			var leg := estimate_seconds(vehicle)
			cumulative = (cumulative + leg + float(config.route_stop_service)) if cumulative < INF else INF
			row["leg_seconds"] = leg
			row["cumulative_seconds"] = cumulative
			cursor = Vector3(_pivot(graph.address_data(address_id), "park_position").x, 0.0,
				_pivot(graph.address_data(address_id), "park_position").y)
		if remaining_by_id.has(order_id):
			var remaining := float(remaining_by_id[order_id])
			row["remaining_seconds"] = remaining
			row["slack_seconds"] = remaining - float(row.cumulative_seconds)
		rows.append(row)
	return rows


# --------------------------------------------------------------------- waypoints


func set_waypoint(position: Variant) -> void:
	if position == null:
		_waypoint = Vector2(INF, INF)
		return
	_waypoint = Vector2(position)


func clear_waypoint() -> void:
	_waypoint = Vector2(INF, INF)


func waypoint() -> Vector2:
	return _waypoint


func has_waypoint() -> bool:
	return is_finite(_waypoint.x) and is_finite(_waypoint.y)


# ------------------------------------------------------------------------ legs


func _drive_leg(address: Dictionary, vehicle: Dictionary) -> Dictionary:
	var entry: Dictionary = vehicle.get("nearest_entry", {})
	var path: Array = vehicle.get("road_path", [])
	var points: Array[Vector3] = [entry.get("position", Vector3.ZERO)]
	for node_id in path:
		points.append(graph.road_node_position(str(node_id)))
	var lanes: Array[Dictionary] = [graph.lane_data(str(entry.get("lane_id", "")))]
	for index in range(1, path.size()):
		lanes.append(graph.lane_between(str(path[index - 1]), str(path[index])))
	var segments: Array[Dictionary] = []
	var first_remaining := float(entry.get("remaining_lane_m", 0.0))
	for index in lanes.size():
		var from_point: Vector3 = points[index]
		var to_point: Vector3 = points[index + 1]
		var distance_m := first_remaining if index == 0 else float(lanes[index].get("length_m", from_point.distance_to(to_point)))
		segments.append({"kind": "drive", "leg": LEG_DRIVE, "from": from_point, "to": to_point,
			"distance_m": maxf(distance_m, 0.0),
			"street_name": str(lanes[index].get("street_name", "")),
			"road_id": str(lanes[index].get("road_id", "")),
			"yaw_deg": float(lanes[index].get("yaw_deg", _yaw_between(from_point, to_point))),
			"node_id": str(path[index]) if index < path.size() else "",
			"maneuver": "straight"})
	var park_point := Vector3(_pivot(address, "park_position").x, 0.0, _pivot(address, "park_position").y)
	var roll_in := Vector3(points[-1].x, 0.0, points[-1].z)
	var park_m := float(vehicle.get("parking_approach_m", 0.0))
	segments.append({"kind": "parking", "leg": LEG_DRIVE, "from": roll_in, "to": park_point,
		"distance_m": maxf(park_m, 0.0), "street_name": "", "road_id": "",
		"yaw_deg": _yaw_between(roll_in, park_point),
		"node_id": str(address.get("parking_id", "")), "maneuver": "park"})
	points.append(park_point)
	var maneuvers: Array[Dictionary] = []
	var along := 0.0
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if index + 1 < segments.size():
			segment["maneuver"] = _turn_kind(float(segment.yaw_deg), float(segments[index + 1].yaw_deg))
		along += float(segment.distance_m)
		var kind := str(segment.maneuver)
		if kind in ["left", "right", "u_turn"]:
			var onto := str(segments[index + 1].get("street_name", ""))
			maneuvers.append({"kind": kind, "leg": LEG_DRIVE, "along_m": along, "at": segment.to,
				"street_name": onto, "node_id": str(segment.node_id)})
		elif kind == "park":
			maneuvers.append({"kind": "park", "leg": LEG_DRIVE, "along_m": along, "at": segment.to,
				"street_name": str(address.get("address", "")), "node_id": str(segment.node_id)})
	var total := 0.0
	for segment in segments:
		total += float(segment.distance_m)
	return {"reachable": true, "points": points, "segments": segments, "maneuvers": maneuvers,
		"distance_m": total}


## The walk leg: from the parking pad when driving (Pip is with the van), or from
## wherever Pip actually stands when on foot. A leaf node cannot reach a house
## door, so the start steps outward to the next plausible walk node instead of
## failing a route the player can plainly make on foot.
func _walk_leg(address: Dictionary, actor_position: Vector3, driving: bool) -> Dictionary:
	var park_point := Vector3(_pivot(address, "park_position").x, 0.0, _pivot(address, "park_position").y)
	var start_id := str(address.get("ped_park_id", ""))
	var start_point := park_point
	var start_offset := 0.0
	if not driving:
		var nearest: Dictionary = graph.pedestrian_nearest_node(actor_position)
		if bool(nearest.get("reachable", false)):
			start_id = str(nearest.get("node_id", ""))
			start_offset = float(nearest.get("distance_m", 0.0))
			start_point = Vector3(actor_position.x, 0.0, actor_position.z)
	var door_id := str(address.get("ped_door_id", ""))
	var path: Dictionary = graph.pedestrian_route(start_id, door_id, _closed_edges)
	if not bool(path.get("reachable", false)) and not driving:
		for candidate in graph.pedestrian_nodes_near(actor_position, 4):
			var node_id := str(candidate.get("node_id", ""))
			if node_id == start_id:
				continue
			var attempt: Dictionary = graph.pedestrian_route(node_id, door_id, _closed_edges)
			if bool(attempt.get("reachable", false)):
				start_id = node_id
				start_offset = float(candidate.get("distance_m", 0.0))
				path = attempt
				break
	if not bool(path.get("reachable", false)):
		return {"reachable": false, "reason": str(path.get("reason", "sidewalk route to the door is blocked"))}
	var path_ids: Array = path.get("path", [])
	var points: Array[Vector3] = [start_point]
	for node_id in path_ids:
		points.append(graph.pedestrian_node_position(str(node_id)))
	var segments: Array[Dictionary] = []
	var along := start_offset
	for index in range(points.size() - 1):
		var from_point: Vector3 = points[index]
		var to_point: Vector3 = points[index + 1]
		var kind := "sidewalk"
		var distance_m := from_point.distance_to(to_point)
		if index == 0:
			distance_m = start_offset
		else:
			var edge: Dictionary = _pedestrian_edge(str(path_ids[index - 1]), str(path_ids[index]))
			kind = str(edge.get("kind", "sidewalk"))
			distance_m = float(edge.get("length_m", distance_m))
		along += maxf(distance_m, 0.0)
		segments.append({"kind": kind, "leg": LEG_WALK, "from": from_point, "to": to_point,
			"distance_m": maxf(distance_m, 0.0), "street_name": "", "road_id": "",
			"yaw_deg": _yaw_between(from_point, to_point),
			"node_id": str(path_ids[index]) if index < path_ids.size() else "", "maneuver": "walk"})
	var maneuvers: Array[Dictionary] = []
	var cursor := 0.0
	for index in segments.size():
		var segment: Dictionary = segments[index]
		cursor += float(segment.distance_m)
		var kind := str(segment.kind)
		if kind == "marked_crossing" and index + 1 < segments.size():
			maneuvers.append({"kind": "cross", "leg": LEG_WALK, "along_m": cursor, "at": segment.to,
				"street_name": "", "node_id": str(segment.node_id)})
	if not segments.is_empty():
		var last: Dictionary = segments[segments.size() - 1]
		maneuvers.append({"kind": "door", "leg": LEG_WALK, "along_m": cursor, "at": last.to,
			"street_name": str(address.get("address", "")), "node_id": str(address.get("ped_door_id", ""))})
	return {"reachable": true, "points": points, "segments": segments, "maneuvers": maneuvers,
		"distance_m": cursor}


func _pedestrian_edge(from_id: String, to_id: String) -> Dictionary:
	for edge in graph.pedestrian_adjacency.get(from_id, []):
		if str(edge.get("to", "")) == to_id:
			return edge
	return {}


# --------------------------------------------------------------------- guidance


func _refresh_guidance() -> void:
	if _route.is_empty():
		_guidance = {}
		return
	if not bool(_route.get("reachable", false)):
		_guidance = {"reachable": false, "leg": LEG_DRIVE, "hint": "NO ROUTE",
			"detail": str(_route.get("reason", "")), "maneuver": {}, "maneuver_distance_m": INF,
			"remaining_m": INF, "progress_m": 0.0, "total_m": 0.0,
			"eta_seconds": INF, "target_address": _target, "address": str(_route.get("label", _target))}
		return
	var driving := _driving
	var leg := LEG_DRIVE if driving else LEG_WALK
	var points: Array = _route.get("drive_points", []) if driving else _route.get("walk_points", [])
	var position := _van_position if driving else _actor_position
	var projection := _project(points, position)
	var total := float(projection.total_m)
	var along := float(projection.along_m)
	var remaining := maxf(total - along, 0.0)
	var hint := ""
	var detail := ""
	var maneuver: Dictionary = {}
	var maneuver_distance := INF
	if driving:
		var park_point: Vector3 = _route.get("park_position", Vector3.ZERO)
		var parked := position.distance_to(park_point) <= float(config.route_arrive_m)
		for entry in _route.get("drive_maneuvers", []):
			if float(entry.along_m) >= along - 0.5:
				maneuver = entry
				break
		if parked:
			hint = "PARK HERE"
			detail = "HOP OUT AND WALK TO THE DOOR"
		elif not maneuver.is_empty():
			maneuver_distance = maxf(float(maneuver.along_m) - along, 0.0)
			hint = _phrase(str(maneuver.kind), str(maneuver.street_name))
		else:
			hint = _phrase("continue", "")
		detail = "ROAD %d M  ·  ETA %s" % [roundi(remaining), _clock(float(_route.get("eta_seconds", INF)))]
	else:
		var door_point: Vector3 = _route.get("door_position", Vector3.ZERO)
		for entry in _route.get("walk_maneuvers", []):
			if float(entry.along_m) >= along - 0.5:
				maneuver = entry
				break
		if not maneuver.is_empty() and str(maneuver.kind) != "door":
			maneuver_distance = maxf(float(maneuver.along_m) - along, 0.0)
			hint = _phrase(str(maneuver.kind), str(maneuver.street_name))
		else:
			maneuver = {}
			hint = "WALK TO " + str(_route.get("label", _target)).to_upper()
		if position.distance_to(door_point) <= float(config.door_range):
			hint = "DOOR — INTERACT"
		detail = "DOOR %d M" % roundi(position.distance_to(door_point))
	var detail_maneuver := ""
	if not maneuver.is_empty() and is_finite(maneuver_distance):
		detail_maneuver = "%d M" % roundi(maneuver_distance)
	_guidance = {"reachable": true, "leg": leg, "hint": hint, "detail": detail,
		"maneuver": maneuver, "maneuver_distance_m": maneuver_distance,
		"maneuver_text": detail_maneuver,
		"remaining_m": remaining, "progress_m": along, "total_m": total,
		"eta_seconds": float(_route.get("eta_seconds", INF)),
		"target_address": _target, "address": str(_route.get("label", _target)),
		"driving": driving}


func _recompute(driving: bool, van_position: Vector3, actor_position: Vector3, reason: String) -> void:
	if _target.is_empty():
		return
	plan(_target, van_position, actor_position, driving, reason)


func _store(route: Dictionary, driving: bool, reason: String) -> void:
	_route = route
	_driving = driving
	_dirty = false
	_cooldown = float(config.route_recompute_cooldown)
	last_reason = reason
	recomputes += 1
	_refresh_guidance()
	route_changed.emit({"reason": reason, "reachable": true, "address_id": _target,
		"eta_seconds": float(route.get("eta_seconds", INF)), "recomputes": recomputes})


func _fail(address_id: String, reason_text: String, code: String, invalidated_by := "plan",
		driving := false) -> Dictionary:
	_route = {"reachable": false, "address_id": address_id, "reason": reason_text, "code": code,
		"label": address_id, "district_id": "", "closed_lanes": _closed_lanes.duplicate(),
		"segments": [], "drive_segments": [], "walk_segments": [],
		"drive_points": [], "walk_points": [], "points": [], "drive_end_index": 0,
		"maneuvers": [], "drive_maneuvers": [], "walk_maneuvers": [], "road_path": [],
		"drive_distance_m": INF, "parking_approach_m": INF, "walk_distance_m": INF,
		"walk_leg_distance_m": INF, "drive_seconds": INF, "walk_seconds": INF,
		"parking_seconds": INF, "allowance_seconds": 0.0, "eta_seconds": INF,
		"park_position": Vector3.ZERO, "door_position": Vector3.ZERO}
	_dirty = false
	_cooldown = float(config.route_recompute_cooldown)
	_driving = driving
	last_reason = invalidated_by
	recomputes += 1
	_refresh_guidance()
	route_changed.emit({"reason": invalidated_by, "reachable": false, "address_id": address_id,
		"code": code, "detail": reason_text, "recomputes": recomputes})
	return _route


# ---------------------------------------------------------------------- helpers


## Ordered result schema shared by the HUD, map and tests.
func schema() -> Array[String]:
	return ["reachable", "address_id", "reason", "code", "label", "district_id", "closed_lanes",
		"segments", "drive_segments", "walk_segments", "drive_points", "walk_points", "points",
		"drive_end_index", "maneuvers", "drive_maneuvers", "walk_maneuvers", "road_path",
		"drive_distance_m", "parking_approach_m", "walk_distance_m", "walk_leg_distance_m",
		"drive_seconds", "walk_seconds", "parking_seconds", "allowance_seconds", "eta_seconds",
		"park_position", "door_position"]


static func _phrase(kind: String, street_name: String) -> String:
	var street := street_name.to_upper()
	match kind:
		"left": return "TURN LEFT ON " + street if not street.is_empty() else "TURN LEFT"
		"right": return "TURN RIGHT ON " + street if not street.is_empty() else "TURN RIGHT"
		"u_turn": return "TURN AROUND"
		"cross": return "CROSS THE ROAD"
		"park": return "PARK AT " + street if not street.is_empty() else "PARK"
		"door": return "DOOR"
	return "CONTINUE ON " + street if not street.is_empty() else "CONTINUE"


static func _clock(seconds: float) -> String:
	if not is_finite(seconds) or seconds <= 0.0:
		return "0:00"
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]


static func _turn_kind(from_yaw: float, to_yaw: float) -> String:
	var delta := wrapf(to_yaw - from_yaw, -180.0, 180.0)
	if absf(delta) < 25.0:
		return "straight"
	if absf(delta) > 150.0:
		return "u_turn"
	return "left" if delta > 0.0 else "right"


static func _yaw_between(from_point: Vector3, to_point: Vector3) -> float:
	var delta := Vector2(to_point.x - from_point.x, to_point.z - from_point.z)
	if delta.length() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(delta.x, delta.y))


static func _project(points: Array, position: Vector3) -> Dictionary:
	if points.size() < 2:
		return {"index": 0, "along_m": 0.0, "offset_m": INF, "total_m": 0.0}
	var p := Vector2(position.x, position.z)
	var best := {"index": 0, "along_m": 0.0, "offset_m": INF}
	var cursor := 0.0
	for index in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var av := Vector2(a.x, a.z)
		var bv := Vector2(b.x, b.z)
		var delta := bv - av
		var length := delta.length()
		var t := 0.0 if length < 0.0001 else clampf((p - av).dot(delta) / (length * length), 0.0, 1.0)
		var offset := p.distance_to(av + delta * t)
		if offset < float(best.offset_m):
			best = {"index": index, "along_m": cursor + length * t, "offset_m": offset}
		cursor += length
	best["total_m"] = cursor
	return best


func _pivot(address: Dictionary, key: String) -> Vector2:
	var row: Variant = address.get(key, null)
	if row is Array and row.size() >= 2:
		return Vector2(float(row[0]), float(row[1]))
	return Vector2.ZERO
