extends SceneTree
## Resource and town-contract validator. Optional -- --town-scene=<fixture>.
var failures: Array[String] = []

func fail(message: String) -> void:
	failures.append(message)
	printerr("TOWN FAIL: ", message)

func scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		fail("missing resource: " + path)
		return null
	var resource = load(path)
	if not resource is PackedScene:
		fail("resource is not PackedScene: " + path)
		return null
	var instance: Node = resource.instantiate()
	if not instance is Node3D:
		fail("root must be Node3D: " + path)
		instance.free()
		return null
	print("check: instantiated ", path, " root=", instance.name, " children=", instance.get_child_count())
	return instance

func _initialize() -> void:
	var town_path := "res://scenes/town.tscn"
	var extra := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town-scene="): town_path = arg.trim_prefix("--town-scene=")
		elif arg.begins_with("--resource="): extra = arg.trim_prefix("--resource=")
	var roots := {"res://assets/town_island.tscn": "TownIsland", "res://assets/town_houses.tscn": "TownHouses", "res://assets/town_props.tscn": "TownProps"}
	for path in roots:
		var node := scene(path)
		if node:
			if node.name != roots[path]: fail("unexpected resource root: " + path)
			node.free()
	if not extra.is_empty():
		var node := scene(extra)
		if node: node.free()
	var town := scene(town_path)
	if town:
		if town.name != "Town": fail("assembled root must be named Town")
		for path in ["Island", "Houses", "Props", "PizzaShop", "StreetDetails", "PlayerSpawn", "VanSpawn", "PizzaShop/PickupPoint"]:
			if not town.get_node_or_null(path) is Node3D: fail("required Node3D missing: " + path)
		for path in ["PlayerSpawn", "VanSpawn"]:
			var spawn := town.get_node_or_null(path)
			if spawn and (typeof(spawn.get_meta("yaw", null)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(spawn.get_meta("yaw", 0)))):
				fail(path + " requires finite numeric yaw metadata")
		var houses := town.get_node_or_null("Houses")
		var addresses := {}
		var numbers := {}
		if houses == null or houses.get_child_count() == 0: fail("Houses must contain delivery addresses")
		else:
			for house in houses.get_children():
				if not house is Node3D:
					fail("house root must be Node3D: " + str(house.name))
					continue
				for path in ["Door", "Park"]:
					if not house.get_node_or_null(path) is Node3D: fail("%s requires %s marker" % [house.name, path])
				for key in ["address", "label"]:
					var value = house.get_meta(key, null)
					if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty(): fail("%s requires nonempty %s" % [house.name, key])
				var address = house.get_meta("address", "")
				if addresses.has(address): fail("duplicate address identity: " + str(address))
				addresses[address] = true
				var number = house.get_meta("number", null)
				if typeof(number) != TYPE_INT or number <= 0: fail("%s requires positive integer number" % house.name)
				elif numbers.has(number): fail("duplicate house number: " + str(number))
				numbers[number] = true
				if typeof(house.get_meta("north", null)) != TYPE_BOOL: fail("%s requires boolean north metadata" % house.name)
		town.free()
	print("TOWN CHECK: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
