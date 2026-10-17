extends Camera3D
## Follow camera. Holds the diorama pitch, swings behind the van while driving,
## and pulls in when a building would block the view.

var target: Node3D
var driving := false
var orbit := false
var yaw := deg_to_rad(48.0)
var _ready_first := true


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var t := target.global_position
	if driving:
		yaw = lerp_angle(yaw, target.rotation.y, clampf(3.2 * delta, 0.0, 1.0))
	elif orbit:
		yaw += delta * 0.11
	var dist := 17.0 if driving else 12.6
	var height := 11.2 if driving else 8.8
	var desired := t + Vector3(sin(yaw), 0, cos(yaw)) * dist + Vector3(0, height, 0)

	var space := get_world_3d().direct_space_state
	var from := t + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
	q.exclude = [target]
	var hit := space.intersect_ray(q)
	if hit:
		var d := from.distance_to(hit.position)
		desired = from + (desired - from).normalized() * maxf(d - 0.7, 3.0)
	if _ready_first:
		global_position = desired
		_ready_first = false
	else:
		global_position = global_position.lerp(desired, clampf((10.0 if driving else 7.5) * delta, 0.0, 1.0))
	var look_at_pos := t + Vector3(0, 1.35, 0)
	if driving:
		look_at_pos += Vector3(sin(target.rotation.y), 0, cos(target.rotation.y)) * 2.6
	look_at(look_at_pos, Vector3.UP)
