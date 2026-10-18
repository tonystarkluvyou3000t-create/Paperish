extends RefCounted
## Stable world IDs and active runtime marker registration. Owns references, not run state.
signal registration_changed(event: Dictionary)

const GraphService = preload("res://scripts/services/world_graph_service.gd")
var graph := GraphService.new()
var town: Node3D
var pip: CharacterBody3D
var van: CharacterBody3D
var camera: Camera3D
var player_spawn: Node3D
var van_spawn: Node3D
var pickup_point: Node3D
var shop_entrance: Node3D
var counter_access: Node3D
var staff_station: Node3D
var ready_stock: Node3D
var houses: Array[Node3D] = []
var world_errors: Array[String] = []
var _markers: Dictionary = {}
var _addresses: Dictionary = {}
var _legacy_ids: Array[String] = []


func bind(root: Node) -> bool:
	town = root.get_node_or_null("Town") as Node3D
	pip = root.get_node_or_null("Pip") as CharacterBody3D
	van = root.get_node_or_null("Van") as CharacterBody3D
	camera = root.get_node_or_null("Camera") as Camera3D
	world_errors.clear()
	houses.clear()
	_markers.clear()
	_addresses.clear()
	_legacy_ids.clear()
	if not graph.load_layout(): world_errors.append(graph.load_error)
	if not town: world_errors.append("Game requires Node3D Town")
	if not pip: world_errors.append("Game requires CharacterBody3D Pip")
	if not van: world_errors.append("Game requires CharacterBody3D Van")
	if not camera: world_errors.append("Game requires Camera3D Camera")
	if town:
		player_spawn = town.get_node_or_null("PlayerSpawn") as Node3D
		van_spawn = town.get_node_or_null("VanSpawn") as Node3D
		pickup_point = town.get_node_or_null("PizzaShop/PickupPoint") as Node3D
		shop_entrance = town.get_node_or_null("PizzaShop/ShopEntrance") as Node3D
		counter_access = town.get_node_or_null("PizzaShop/CounterAccess") as Node3D
		staff_station = town.get_node_or_null("PizzaShop/StaffStation") as Node3D
		ready_stock = town.get_node_or_null("PizzaShop/ReadyStock") as Node3D
		for path in ["PlayerSpawn", "VanSpawn", "PizzaShop/PickupPoint"]:
			if not town.get_node_or_null(path) is Node3D:
				world_errors.append("Town requires Node3D: " + path)
		var houses_root := town.get_node_or_null("Houses")
		if houses_root:
			for child in houses_root.get_children():
				if not child is Node3D:
					world_errors.append("Town/Houses children must be Node3D: " + str(child.name))
					continue
				var house := child as Node3D
				houses.append(house)
				for marker_name in ["Door", "Park"]:
					if not house.get_node_or_null(marker_name) is Node3D:
						world_errors.append("House %s requires Node3D %s" % [house.name, marker_name])
				var address_id := str(house.get_meta("address_id", house.get_meta("address", "")))
				var address_text := str(house.get_meta("address", ""))
				if address_id.strip_edges().is_empty() or address_text.strip_edges().is_empty():
					world_errors.append("House %s requires nonempty address and address_id metadata" % house.name)
				elif _addresses.has(address_id):
					world_errors.append("Duplicate house address ID: " + address_id)
				else:
					_addresses[address_id] = house
					register_marker(address_id, "address", house)
				for marker_name in ["Door", "Park"]:
					var marker := house.get_node_or_null(marker_name) as Node3D
					if marker:
						var fallback_prefix := "door" if marker_name == "Door" else "parking"
						register_marker(str(marker.get_meta("world_id", fallback_prefix + ":" + address_id)), fallback_prefix, marker)
		if houses.is_empty():
			world_errors.append("Town/Houses requires at least one delivery address with Door and Park")
		_register_tree_markers(town)
		var legacy: Variant = graph.layout.get("legacy_destination_order", [])
		for value in legacy: _legacy_ids.append(str(value))
	if pip and not (pip.get_node_or_null("Collision") is CollisionShape3D
			and pip.get_node("Collision").shape is CapsuleShape3D):
		world_errors.append("Pip/Collision requires CapsuleShape3D for safe exit probes")
	if van and not (van.get_node_or_null("Collision") is CollisionShape3D
			and van.get_node("Collision").shape is BoxShape3D):
		world_errors.append("Van/Collision requires BoxShape3D for safe exit probes")
	for message in world_errors:
		push_error("World contract: " + message)
	return world_errors.is_empty()


func _register_tree_markers(node: Node) -> void:
	if node is Node3D and node.has_meta("world_id"):
		var kind := str(node.get_meta("kind", "marker"))
		register_marker(str(node.get_meta("world_id")), kind, node as Node3D)
	for child in node.get_children(): _register_tree_markers(child)


func register_marker(marker_id: String, kind: String, node: Node3D) -> bool:
	if marker_id.strip_edges().is_empty() or not is_instance_valid(node): return false
	if _markers.has(marker_id):
		if _markers[marker_id] == node: return true
		world_errors.append("Duplicate world marker ID: " + marker_id)
		return false
	_markers[marker_id] = node
	registration_changed.emit({"id": marker_id, "kind": kind, "registered": true})
	return true


func unregister_marker(marker_id: String) -> void:
	if not _markers.has(marker_id): return
	_markers.erase(marker_id)
	registration_changed.emit({"id": marker_id, "kind": "marker", "registered": false})


func marker(marker_id: String) -> Node3D:
	var node: Node3D = _markers.get(marker_id) as Node3D
	return node if is_instance_valid(node) else null


func address(address_id: String) -> Node3D:
	return _addresses.get(address_id) as Node3D


func address_record(address_id: String) -> Dictionary:
	return graph.address_data(address_id)


func ids() -> Array[String]:
	var result: Array[String] = []
	var active: Dictionary = {}
	for house in houses:
		if is_instance_valid(house):
			active[str(house.get_meta("address_id", house.get_meta("address", "")))] = true
	for row in graph.layout.get("addresses", []):
		var address_id := str(row.get("id", ""))
		if active.has(address_id): result.append(address_id)
	return result


func destination(address_id: String) -> Node3D:
	var found := address(address_id)
	if found: return found
	# Compatibility for callers that still have the display string.
	for house in houses:
		if str(house.get_meta("address", "")) == address_id: return house
	return null


func legacy_id(index: int) -> String:
	if index < 0 or index >= _legacy_ids.size(): return ""
	return _legacy_ids[index]
