extends SceneTree
## Optional portable mesh exports, in addition to the editable native scenes.
func _initialize() -> void:
	for asset in ["land", "pizza_shop", "pizza_van", "pip", "street_details"]:
		var scene: PackedScene = load("res://assets/%s.tscn" % asset)
		var instance := scene.instantiate()
		root.add_child(instance)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_scene(instance, state)
		if error == OK:
			error = document.write_to_filesystem(state, "res://assets/%s.glb" % asset)
		if error != OK:
			push_error("Export failed for %s: %s" % [asset, error_string(error)])
			quit(1)
			return
		print("Exported: ", asset)
		instance.free()
	quit()
