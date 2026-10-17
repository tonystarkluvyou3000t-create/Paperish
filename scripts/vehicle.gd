extends CharacterBody3D
## Arcade delivery van: throttle/brake/reverse, speed-sensitive steering, spinning
## faceted wheels, engine hum and a light body lean. Movement is CharacterBody so
## the van never tips over or tunnels - it bumps, slides and keeps the diorama feel.

signal honked

const MAX_SPEED := 13.5
const MAX_REVERSE := 5.0
const ACCEL := 8.5
const BRAKE := 18.0
const DRAG := 1.7
const MAX_YAW := 2.05
const WHEEL_R := 0.43

var input_enabled := true
var speed := 0.0
var steer := 0.0
var wheel_spin := 0.0
var braking := false
var autopilot := Vector3.INF     # dev/test hook: drive to this spot

@onready var visual: Node3D = $Visual
var _wheels: Array[Node3D] = []
var _front: Array[Node3D] = []
var _engine: AudioStreamPlayer3D


func _ready() -> void:
	var inner := visual.get_node_or_null("Van_collision")
	if inner is StaticBody3D:
		# keep the art's static collider for people walking around the parked van,
		# but keep it off the van's own collision mask
		(inner as StaticBody3D).collision_layer = 4
		(inner as StaticBody3D).collision_mask = 0
	collision_layer = 4
	collision_mask = 1
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var n := child.name.to_lower()
		if n.begins_with("octagonal_tyre") or n.begins_with("wheel_hub") or n.begins_with("hub_center"):
			_wheels.append(child as Node3D)
			if (child as Node3D).position.z > 0.5:
				_front.append(child as Node3D)
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = load("res://assets/audio/engine.wav")
	_engine.unit_size = 6.0
	_engine.max_distance = 34.0
	_engine.volume_db = -4.0
	_engine.position = Vector3(0, 0.9, 1.5)
	add_child(_engine)
	if _engine.stream is AudioStreamWAV:
		(_engine.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_engine.play()


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if autopilot != Vector3.INF:
		var to := autopilot - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 3.2:
			# inside the arrival ring: brake until actually stopped, then release
			# the hook. Clearing autopilot while still rolling left only DRAG to
			# shed the speed, so the van coasted 20+ m past its target.
			handbrake = true
			if absf(speed) <= 0.4:
				speed = 0.0
				autopilot = Vector3.INF
		else:
			var diff := wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)
			steer_in = clampf(diff * 1.9, -1.0, 1.0)
			if absf(diff) > 2.3 and speed > 1.5:
				throttle = -1.0
			elif absf(diff) > 1.0:
				throttle = -0.3
			else:
				throttle = 1.0 if speed < MAX_SPEED * 0.75 else 0.0
	elif input_enabled:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_in = Input.get_axis("move_right", "move_left")
		handbrake = Input.is_action_pressed("handbrake")
		if Input.is_action_just_pressed("honk"):
			honked.emit()

	braking = false
	if throttle > 0.05:
		speed = move_toward(speed, MAX_SPEED * throttle, ACCEL * delta)
	elif throttle < -0.05:
		if speed > 0.5:
			braking = true
			speed = move_toward(speed, 0.0, BRAKE * delta)
		else:
			speed = move_toward(speed, MAX_REVERSE * throttle, ACCEL * 0.8 * delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	if handbrake:
		braking = speed > 0.5
		speed = move_toward(speed, 0.0, BRAKE * 1.5 * delta)

	steer = move_toward(steer, steer_in, 6.5 * delta)
	var grip := clampf(absf(speed) / 2.2, 0.0, 1.0)
	grip *= 1.0 - 0.32 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)
	if handbrake:
		grip *= 1.35
	rotation.y += steer * MAX_YAW * grip * delta * (1.0 if speed >= 0.0 else -1.0)

	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 24.0 * delta
	move_and_slide()

	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is CharacterBody3D and other != self:
			(other as CharacterBody3D).apply_push(-c.get_normal() * (2.0 + absf(speed) * 0.4))
		if c.get_normal().dot(fwd) < -0.55:
			speed *= 0.3

	wheel_spin += (speed / WHEEL_R) * delta
	for w in _wheels:
		var sa := steer * 0.52 if w in _front else 0.0
		w.rotation = Vector3(wheel_spin, sa, PI * 0.5)
	visual.rotation.z = lerpf(visual.rotation.z, clampf(-steer * speed * 0.010, -0.10, 0.10),
		6.0 * delta)
	visual.rotation.x = lerpf(visual.rotation.x, -throttle * 0.02, 6.0 * delta)
	if _engine:
		_engine.pitch_scale = 0.72 + absf(speed) / MAX_SPEED * 0.8
