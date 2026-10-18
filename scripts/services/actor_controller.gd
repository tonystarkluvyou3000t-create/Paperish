extends Node
## Exclusive movement and safe vehicle transitions; no order or cash authority.
signal transitioned(driving: bool)
signal rejected(message: String)
const Layers = preload("res://scripts/collision_layers.gd")
enum Mode { FOOT, DRIVING }
var mode := Mode.FOOT
var driving: bool:
	get: return mode == Mode.DRIVING
var pip: CharacterBody3D
var van: CharacterBody3D
var camera: Camera3D
var session: Node
var config: Resource

func configure(player: CharacterBody3D, vehicle: CharacterBody3D, rig: Camera3D, flow: Node, balance: Resource) -> void:
	pip = player
	van = vehicle
	camera = rig
	session = flow
	config = balance
	session.changed.connect(_on_session_changed)

func _on_session_changed(_event: Dictionary) -> void:
	if session.flow != session.Flow.PLAYING: cancel_motion()
	if session.flow == session.Flow.PLAYING: camera.orbit = false
	sync()

func reset(player_spawn: Node3D, van_spawn: Node3D) -> void:
	mode = Mode.FOOT
	cancel_motion()
	pip.visible = true
	pip.collision_layer = Layers.PLAYER
	pip.get_node("Collision").set_deferred("disabled", false)
	pip.locked_yaw = NAN
	pip.global_position = player_spawn.global_position
	pip.rotation = Vector3(0, deg_to_rad(float(player_spawn.get_meta("yaw", 0.0))), 0)
	van.global_position = van_spawn.global_position
	van.rotation = Vector3(0, deg_to_rad(float(van_spawn.get_meta("yaw", 90.0))), 0)
	van.wheel_spin = 0
	van.visual.rotation = Vector3.ZERO
	camera.target = pip
	camera.driving = false
	camera.orbit = true
	camera.yaw = pip.rotation.y + deg_to_rad(140.0)
	camera._ready_first = true
	camera.set_physics_process(true)
	sync()

func sync() -> void:
	var active: bool = session.flow == session.Flow.PLAYING and not session.paused
	pip.input_enabled = active and not driving
	van.input_enabled = active and driving
	pip.set_physics_process(active and not driving)
	# The parked van still settles under gravity/drag, but cannot read input or
	# run a dev controller. Terminal/title states freeze both actors entirely.
	van.set_physics_process(active)


func cancel_motion() -> void:
	pip.autopilot = Vector3.INF
	van.autopilot = Vector3.INF
	pip.velocity = Vector3.ZERO
	van.velocity = Vector3.ZERO
	van.speed = 0.0
	van.steer = 0.0
	van.braking = false


func stopped() -> bool:
	var horizontal := Vector3(van.velocity.x, 0, van.velocity.z)
	return absf(van.speed) <= config.stopped_speed and horizontal.length() <= config.stopped_speed


func _reject_vehicle(message: String) -> void:
	rejected.emit(message)


func enter() -> bool:
	if session.flow != session.Flow.PLAYING or session.paused or driving:
		return false
	if pip.global_position.distance_to(van.global_position) >= config.van_range:
		return false
	if not stopped():
		_reject_vehicle("WAIT FOR THE VAN TO STOP")
		return false
	mode = Mode.DRIVING
	pip.autopilot = Vector3.INF
	van.autopilot = Vector3.INF
	pip.velocity = Vector3.ZERO
	pip.visible = false
	pip.collision_layer = Layers.NONE
	pip.get_node("Collision").set_deferred("disabled", true)
	sync()
	camera.target = van
	camera.driving = true
	transitioned.emit(true)
	return true


func exit() -> bool:
	if session.flow != session.Flow.PLAYING or session.paused or not driving:
		return false
	if not stopped():
		_reject_vehicle("STOP THE VAN TO EXIT")
		return false
	var candidate := _find_exit_position()
	if candidate == Vector3.INF:
		_reject_vehicle("EXIT BLOCKED · MOVE TO A CLEAR, LEVEL SPOT")
		return false
	# Do not brake here: the stopped-speed check must pass before any mutation.
	mode = Mode.FOOT
	van.autopilot = Vector3.INF
	pip.global_position = candidate
	pip.velocity = Vector3.ZERO
	pip.autopilot = Vector3.INF
	pip.rotation.y = van.rotation.y + PI * 0.5
	pip.visible = true
	pip.collision_layer = Layers.PLAYER
	pip.get_node("Collision").set_deferred("disabled", false)
	sync()
	camera.target = pip
	camera.driving = false
	transitioned.emit(false)
	return true


func _find_exit_position() -> Vector3:
	var collision := pip.get_node("Collision") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D
	var van_collision := van.get_node("Collision") as CollisionShape3D
	var van_shape := van_collision.shape as BoxShape3D
	var radius := capsule.radius * maxf(pip.global_basis.get_scale().x, pip.global_basis.get_scale().z)
	var side: float = van_shape.size.x * 0.5 + radius + config.exit_clearance
	var rear: float = van_shape.size.z * 0.5 + radius + config.exit_clearance
	var space := pip.get_world_3d().direct_space_state
	var excluded: Array[RID] = [pip.get_rid(), van.get_rid()]
	var yaw := van.rotation.y + PI * 0.5
	var basis := Basis(Vector3.UP, yaw).scaled(pip.global_basis.get_scale())
	var foot_offset := (basis * collision.position).y - capsule.height * basis.y.length() * 0.5
	for local_offset in [Vector3(side, 0, 0.15), Vector3(-side, 0, 0.15), Vector3(0, 0, -rear)]:
		var pos: Vector3 = van.global_transform * (van_collision.position * Vector3(1, 0, 1) + local_offset)
		# Ray origins are at feet height plus a small step, never on the roof.
		# Check a footprint, not only its center: ledges and missing support fail.
		var supported := true
		var floor_height := 0.0
		for sample in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var point: Vector3 = pos + sample * radius * 0.8
			var ray := PhysicsRayQueryParameters3D.create(
				point + Vector3.UP * config.exit_max_step, point + Vector3.DOWN * config.exit_max_drop, Layers.WORLD)
			ray.exclude = excluded
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.normal.dot(Vector3.UP) < cos(pip.floor_max_angle):
				supported = false
				break
			if sample == Vector3.ZERO:
				floor_height = hit.position.y
			elif absf(hit.position.y - floor_height) > config.exit_max_step:
				supported = false
				break
		if not supported:
			continue
		pos.y = floor_height - foot_offset + config.exit_floor_gap
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(basis, pos) * collision.transform
		query.collision_mask = pip.collision_mask
		query.exclude = excluded
		query.margin = 0.02
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# A clear endpoint beyond a thin wall is not an exit. Sweep the same
		# capsule from the van to the endpoint, ignoring only Pip and this van.
		var start := Vector3(van.global_position.x, pos.y, van.global_position.z)
		query.transform = Transform3D(basis, start) * collision.transform
		query.motion = pos - start
		var sweep := space.cast_motion(query)
		if sweep.size() == 2 and sweep[0] >= 1.0:
			return pos
	return Vector3.INF



func on_settlement(_event: Dictionary) -> void:
	pip.autopilot = Vector3.INF
	van.autopilot = Vector3.INF
