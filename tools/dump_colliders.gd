extends SceneTree
## Dump every StaticBody3D collider in the town for offline analysis.
##   godot --headless --path . --script tools/dump_colliders.gd
var _town: Node3D

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/town.tscn")
	_town = scene.instantiate()
	root.add_child(_town)

func _process(_delta: float) -> bool:
	var n := 0
	for body in _town.find_children("*", "StaticBody3D", true, false):
		var b := body as StaticBody3D
		var parts: Array[String] = []
		for c in b.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			if cs.shape is BoxShape3D:
				var sz: Vector3 = (cs.shape as BoxShape3D).size
				var gp: Vector3 = cs.global_position
				parts.append("box %s @ %s" % [str(sz), str(_r2(gp))])
			elif cs.shape != null:
				parts.append(str(cs.shape.get_class()))
			else:
				parts.append("null-shape")
		print("%-46s layer=%d mask=%d  %s" % [str(b.get_path()), b.collision_layer,
			b.collision_mask, ", ".join(parts)])
		n += 1
	print("total static bodies: ", n)
	return true


func _r2(v: Vector3) -> Vector3:
	return (v * 100.0).round() / 100.0
