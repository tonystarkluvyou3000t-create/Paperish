extends SceneTree
## Load each saved asset and portable export to catch broken resources.
func _initialize() -> void:
	var pieces := 0
	for name in ["land", "pizza_shop", "pizza_van", "pip", "street_details"]:
		for extension in ["tscn", "glb"]:
			var path := "res://assets/%s.%s" % [name, extension]
			var resource := load(path) as PackedScene
			if resource == null:
				push_error("Could not load " + path)
				quit(1)
				return
			var instance := resource.instantiate()
			var meshes := instance.find_children("*", "MeshInstance3D", true, false)
			if meshes.is_empty():
				push_error("No meshes in " + path)
				quit(1)
				return
			print("Verified ", name, ".", extension, ": ", meshes.size(), " mesh pieces")
			if extension == "tscn":
				pieces += meshes.size()
			instance.free()
	print("All ten asset files loaded. Original mesh pieces: ", pieces)
	quit()
