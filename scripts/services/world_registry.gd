extends RefCounted
## Scene contracts and stable destination lookup. Owns references, not run state.
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

func bind(root: Node) -> bool:
	town = root.get_node_or_null("Town") as Node3D
	pip = root.get_node_or_null("Pip") as CharacterBody3D
	van = root.get_node_or_null("Van") as CharacterBody3D
	camera = root.get_node_or_null("Camera") as Camera3D
	world_errors.clear()
	houses.clear()
	if not town:
		world_errors.append("Game requires Node3D Town")
	if not pip:
		world_errors.append("Game requires CharacterBody3D Pip")
	if not van:
		world_errors.append("Game requires CharacterBody3D Van")
	if not camera:
		world_errors.append("Game requires Camera3D Camera")
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
		var addresses := {}
		if houses_root:
			for house in houses_root.get_children():
				if not house is Node3D:
					world_errors.append("Town/Houses children must be Node3D: " + str(house.name))
					continue
				houses.append(house)
				for marker in ["Door", "Park"]:
					if not house.get_node_or_null(marker) is Node3D:
						world_errors.append("House %s requires Node3D %s" % [house.name, marker])
				var address = house.get_meta("address", "")
				if not address is String or str(address).strip_edges().is_empty():
					world_errors.append("House %s requires nonempty address metadata" % house.name)
				elif addresses.has(address):
					world_errors.append("Duplicate house address: " + address)
				addresses[address] = true
		if houses.is_empty():
			world_errors.append("Town/Houses requires at least one delivery house with Door and Park")
	if pip and not (pip.get_node_or_null("Collision") is CollisionShape3D
			and pip.get_node("Collision").shape is CapsuleShape3D):
		world_errors.append("Pip/Collision requires CapsuleShape3D for safe exit probes")
	if van and not (van.get_node_or_null("Collision") is CollisionShape3D
			and van.get_node("Collision").shape is BoxShape3D):
		world_errors.append("Van/Collision requires BoxShape3D for safe exit probes")
	for message in world_errors:
		push_error("World contract: " + message)
	return world_errors.is_empty()


func ids() -> Array[String]:
	var result: Array[String] = []
	for house in houses: result.append(str(house.get_meta("address")))
	return result

func destination(id: String) -> Node3D:
	for house in houses:
		if str(house.get_meta("address")) == id: return house
	return null

func legacy_id(index: int) -> String:
	if index < 0 or index >= houses.size(): return ""
	return str(houses[index].get_meta("address"))
