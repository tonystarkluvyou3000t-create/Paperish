extends CharacterBody3D
## Pip on foot: camera-relative walking with procedural limb swing and a
## stack of pizza boxes in his left hand.

signal footstep

const Layers = preload("res://scripts/collision_layers.gd")

const WALK_SPEED := 4.3
const ACCEL := 26.0
const DECEL := 30.0
const TURN_SPEED := 12.0
const GRAVITY := 24.0

var cargo_source: Node
var carrying: int:
	get: return cargo_source.cargo_count if cargo_source else 0
var input_enabled := true
var phase := 0.0
var walk := 0.0
var locked_yaw := NAN            # set while driving so he sits still
var autopilot := Vector3.INF     # dev/test hook: walk to this spot

@onready var visual: Node3D = $Visual
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D
var _body: Node3D
var _box_tf: Transform3D
var _box_art: Array[Node3D] = []
var _box_extra: Array[Node3D] = []
var _last_step := 0
var _idle_t := 0.0


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.VEHICLE
	_leg_l = visual.get_node("LeftLeg")
	_leg_r = visual.get_node("RightLeg")
	_arm_l = visual.get_node("LeftArm")
	_arm_r = visual.get_node("RightArm")
	_head = visual.get_node("Head")
	_body = visual.get_node("Body")
	for n in ["Pizza_box", "Pizza_box_lid", "Box_red_stripe", "Box_logo", "Box_cheese"]:
		var node := visual.get_node_or_null(n)
		if node:
			_box_art.append(node)
	if not _box_art.is_empty():
		# the box was authored at the left hand; parent it to the arm pivot so it
		# travels with the arm, then remember where it sits
		_box_tf = (_box_art[0] as Node3D).transform
		for node in _box_art:
			node.reparent(_arm_l, true)
		_box_tf = (_box_art[0] as Node3D).transform
		_build_stack()
	set_carrying(0)


func _build_stack() -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.64, 0.13, 0.6)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("f8e5bc")
	body_mat.roughness = 0.85
	body_mesh.material = body_mat
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.67, 0.04, 0.63)
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color("fff3d7")
	lid_mat.roughness = 0.85
	lid_mesh.material = lid_mat
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.48, 0.06, 0.012)
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color("c84436")
	stripe_mat.roughness = 0.85
	stripe_mesh.material = stripe_mat
	for i in range(1, 3):
		var holder := Node3D.new()
		holder.transform = _box_tf.translated_local(Vector3(0, 0.075 * i, 0))
		_arm_l.add_child(holder)
		var a := MeshInstance3D.new()
		a.mesh = body_mesh
		var b := MeshInstance3D.new()
		b.mesh = lid_mesh
		b.position = Vector3(0, 0.08, 0)
		var c := MeshInstance3D.new()
		c.mesh = stripe_mesh
		c.position = Vector3(0, 0.005, 0.31)
		holder.add_child(a)
		holder.add_child(b)
		holder.add_child(c)
		_box_extra.append(holder)


func set_carrying(n: int) -> void:
	for i in _box_art.size():
		_box_art[i].visible = n > 0
	for i in _box_extra.size():
		_box_extra[i].visible = n > i + 1


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if input_enabled and autopilot != Vector3.INF:
		var flat := autopilot - global_position
		flat.y = 0.0
		if flat.length() > 1.2:
			dir = flat.normalized()
		else:
			autopilot = Vector3.INF
	elif input_enabled:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if iv.length() > 0.02:
			var cam := get_viewport().get_camera_3d()
			var fwd := Vector3.FORWARD
			var right := Vector3.RIGHT
			if cam:
				fwd = -cam.global_transform.basis.z
				right = cam.global_transform.basis.x
			fwd.y = 0
			right.y = 0
			dir = (fwd.normalized() * -iv.y + right.normalized() * iv.x).normalized()

	var speed_max := WALK_SPEED * (1.0 - 0.06 * float(carrying))
	var hv := Vector3(velocity.x, 0, velocity.z)
	if dir != Vector3.ZERO:
		hv = hv.move_toward(dir * speed_max, ACCEL * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if dir != Vector3.ZERO and is_nan(locked_yaw):
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), TURN_SPEED * delta)
	_animate(delta, hv.length(), dir != Vector3.ZERO)


func _animate(delta: float, sp: float, moving: bool) -> void:
	walk = clampf(sp / WALK_SPEED, 0.0, 1.0)
	if moving:
		phase += delta * (3.4 + 6.2 * walk)
	elif idle_rest():
		phase = lerp_angle(phase, round(phase / PI) * PI, clampf(delta * 6.0, 0, 1))
	var swing := sin(phase) * walk
	_leg_l.rotation.x = swing * 0.62
	_leg_r.rotation.x = -swing * 0.62
	_arm_r.rotation.x = -swing * 0.5
	if carrying > 0:
		_arm_l.rotation.x = -0.08 + swing * 0.03
	else:
		_arm_l.rotation.x = swing * 0.5
	_idle_t += delta
	var breathe := sin(_idle_t * 1.6) * 0.02 * (1.0 - walk)
	_head.rotation.y = sin(_idle_t * 0.55) * 0.06 * (1.0 - walk)
	_head.rotation.x = breathe
	_body.rotation.x = walk * 0.07
	visual.position.y = absf(sin(phase)) * 0.05 * walk
	visual.rotation.z = sin(phase * 1.0) * 0.02 * walk
	var step_now := int(phase / PI)
	if step_now != _last_step and walk > 0.35:
		_last_step = step_now
		footstep.emit()


func idle_rest() -> bool:
	return walk < 0.12


func apply_push(push: Vector3) -> void:
	velocity += push
