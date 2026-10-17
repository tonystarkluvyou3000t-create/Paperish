extends Node3D
## Presentation camera only. This scene (and the town preview) contain no game systems.
##   --capture            overhead diorama of scenes/pizza_corner.tscn
##   --capture-pip        close-up of Pip on a stage
##   --capture-town       overhead diorama of scenes/town.tscn
##   --capture-town-street  street level in front of the pizza shop
##   --capture-town-top   straight top-down plan view of the town
##   --capture-town-houses  close view of the north side customer houses
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shots := {
		"--capture-town": ["res://previews/town.png", Vector3(52.9, 42.4, 67.1), Vector3(0, 0.5, 0), 78.0, true],
		"--capture-town-street": ["res://previews/town_street.png", Vector3(13.0, 6.0, -7.0), Vector3(-1.0, 1.6, 9.0), 42.0, false],
		"--capture-town-top": ["res://previews/town_top.png", Vector3(0, 130, 0.5), Vector3(0, 0, 0), 66.0, true],
		"--capture-town-houses": ["res://previews/town_houses.png", Vector3(25.0, 6.5, 5.0), Vector3(25.0, 1.6, -11.0), 40.0, false],
	}
	if "--capture-pip" in args:
		_capture_pip()
		return
	for key in shots:
		if key in args:
			var shot: Array = shots[key]
			_shot(shot[0], shot[1], shot[2], shot[3], shot[4])
			return
	# default diorama of the art-corner scene
	$Camera.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	if "--capture" in args:
		_save("res://previews/pizza_corner.png")


func _shot(output: String, pos: Vector3, look: Vector3, size: float, ortho: bool) -> void:
	var cam := $Camera as Camera3D
	cam.position = pos
	cam.look_at(look, Vector3.UP)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = size
	_save(output)


func _capture_pip() -> void:
	for child in [$Land, $PizzaShop, $PizzaVan, $StreetDetails]:
		child.hide()
	$Pip.position = Vector3.ZERO
	$Pip.rotation = Vector3.ZERO
	$Camera.position = Vector3(3, 2.4, 5)
	$Camera.size = 3.0
	$Camera.look_at(Vector3(0, 1.05, 0))
	var stage := MeshInstance3D.new()
	var platform := BoxMesh.new()
	platform.size = Vector3(2.2, 0.1, 1.8)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("88ae65")
	platform.material = material
	stage.mesh = platform
	stage.position.y = -0.055
	add_child(stage)
	_save("res://previews/pip.png")


func _save(output: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output)
	print("Preview saved: ", output)
	get_tree().quit()
