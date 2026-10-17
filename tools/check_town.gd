extends SceneTree
## Load each generated town resource one at a time, reporting progress to stdout.
func _initialize() -> void:
	print("check: start")
	for path in ["res://assets/town_island.tscn", "res://assets/town_houses.tscn",
			"res://assets/town_props.tscn", "res://scenes/town.tscn"]:
		print("check: loading ", path)
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		print("check: loaded   ", path, " -> ", res)
		if res is PackedScene:
			var inst: Node = (res as PackedScene).instantiate()
			print("check: instantiated, children=", inst.get_child_count())
			inst.free()
	print("check: done")
	quit(0)
