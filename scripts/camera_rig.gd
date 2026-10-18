extends Camera3D
## Player-controlled follow camera. Four modes share one smoothed pose:
## TITLE_ORBIT (the independent title diorama), FOLLOW (on-foot orbit),
## CHASE (driving, recenters after an idle grace) and FREE (an independent
## detached camera that freezes gameplay through the session's modal reason).
##
## The rig owns camera mode, yaw/pitch, zoom and the collision boom. It reads
## ActorController's `target`/`driving` contract and SessionService's flow/pause;
## it never touches orders, cargo, cash or actor bodies. It is the only consumer
## of the `cam_*` actions: while any non-free modal owns pause the rig ignores
## them entirely, and the free camera is the one exception that keeps its own
## controls live.

const Layers = preload("res://scripts/collision_layers.gd")

enum Mode { TITLE_ORBIT, FOLLOW, CHASE, FREE }
const FREE_MODAL := &"free_camera"

# ---- ActorController contract (also covered by phase-01 checks)
var target: Node3D
var driving := false
var orbit := false
var yaw := deg_to_rad(48.0)
var _ready_first := true

# ---- wiring and tuning (copied from Balance in configure(); never run state)
var session: Node
var invert_y := false
var mouse_sensitivity := 0.0032
var pad_sensitivity := 2.6
var zoom_step := 1.6
var foot_dist_min := 6.5
var foot_dist_max := 24.0
var foot_dist_default := 14.6
var foot_pitch_min := 8.0
var foot_pitch_max := 74.0
var foot_pitch_default := 30.0
var foot_recenter_offset := 140.0
var chase_dist_min := 9.0
var chase_dist_max := 30.0
var chase_dist_default := 19.6
var chase_pitch_min := 6.0
var chase_pitch_max := 55.0
var chase_pitch_default := 30.0
var recenter_grace := 1.2
var recenter_rate := 2.4
var transition_rate := 3.2
var extend_rate := 5.0
var pitch_ease := 70.0
var collision_radius := 0.35
var collision_skin := 0.25
var foot_min_boom := 1.1
var chase_min_boom := 2.2
var occlude_fade_start := 4.5
var occlude_fade_end := 1.5
var occlude_fade_max := 0.55
var free_speed := 9.0
var free_boost := 3.0
var free_extent := 320.0
var free_floor := -8.0
var free_ceiling := 150.0
var free_return_time := 0.35

# ---- smoothed run state (public reads are for the read model and tests)
var pitch := deg_to_rad(30.0)
var distance_target := 14.6      # requested boom length after zoom clamps
var distance := 14.6             # eased boom length
var boom := 14.6                 # final boom length, always <= allowed_boom
var allowed_boom := 14.6         # wall-clamped cap for this frame
var look_idle := 999.0           # seconds since the last manual driving look
var _foot_distance := 14.6
var _chase_distance := 19.6
var _last_mode := Mode.TITLE_ORBIT
var _dragging := false
var _recenter_pending := false
var _recenter_active := false
var _free := false
var _free_yaw := 0.0
var _free_pitch := 0.0
var _free_position := Vector3.ZERO
var _saved: Dictionary = {}
var _blend_from := Vector3.ZERO
var _blend_t := 0.0
var _fade_value := -1.0
var _fade_target: Node3D
var _fade_nodes: Array[GeometryInstance3D] = []


func _ready() -> void:
	# The free camera and its modal stay live while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	# Losing window focus mid-drag (alt-tab, click-away) must not strand a
	# captured cursor: drop the drag and hand the mouse back. Regaining focus
	# re-grabs only for the free camera, which is a mouse-look mode.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		if _free and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure(flow: Node, balance: Resource) -> void:
	session = flow
	if session and not session.changed.is_connected(_on_session_changed):
		session.changed.connect(_on_session_changed)
	if balance:
		mouse_sensitivity = balance.cam_mouse_sensitivity
		pad_sensitivity = balance.cam_pad_sensitivity
		invert_y = balance.cam_invert_y
		zoom_step = balance.cam_zoom_step
		foot_dist_min = balance.cam_foot_dist_min
		foot_dist_max = balance.cam_foot_dist_max
		foot_dist_default = balance.cam_foot_dist_default
		foot_pitch_min = balance.cam_foot_pitch_min
		foot_pitch_max = balance.cam_foot_pitch_max
		foot_pitch_default = balance.cam_foot_pitch_default
		foot_recenter_offset = balance.cam_foot_recenter_offset
		chase_dist_min = balance.cam_chase_dist_min
		chase_dist_max = balance.cam_chase_dist_max
		chase_dist_default = balance.cam_chase_dist_default
		chase_pitch_min = balance.cam_chase_pitch_min
		chase_pitch_max = balance.cam_chase_pitch_max
		chase_pitch_default = balance.cam_chase_pitch_default
		recenter_grace = balance.cam_recenter_grace
		recenter_rate = balance.cam_recenter_rate
		transition_rate = balance.cam_transition_rate
		extend_rate = balance.cam_extend_rate
		pitch_ease = balance.cam_pitch_ease
		collision_radius = balance.cam_collision_radius
		collision_skin = balance.cam_collision_skin
		foot_min_boom = balance.cam_foot_min_boom
		chase_min_boom = balance.cam_chase_min_boom
		occlude_fade_start = balance.cam_occlude_fade_start
		occlude_fade_end = balance.cam_occlude_fade_end
		occlude_fade_max = balance.cam_occlude_fade_max
		free_speed = balance.cam_free_speed
		free_boost = balance.cam_free_boost
		free_extent = balance.cam_free_extent
		free_floor = balance.cam_free_floor
		free_ceiling = balance.cam_free_ceiling
		free_return_time = balance.cam_free_return_time
	_foot_distance = foot_dist_default
	_chase_distance = chase_dist_default
	distance_target = foot_dist_default
	distance = foot_dist_default
	boom = foot_dist_default
	allowed_boom = foot_dist_default
	pitch = deg_to_rad(foot_pitch_default)


## Restart/title reset. Called by ActorController before it repoints the target.
func reset_state() -> void:
	if _free:
		_finish_free(true)
	_recenter_pending = false
	_recenter_active = false
	_dragging = false
	look_idle = 999.0
	_foot_distance = foot_dist_default
	_chase_distance = chase_dist_default
	distance_target = foot_dist_default
	distance = foot_dist_default
	boom = foot_dist_default
	allowed_boom = foot_dist_default
	pitch = deg_to_rad(foot_pitch_default)
	_blend_t = 0.0
	_ready_first = true
	_apply_fade(0.0)


# ------------------------------------------------------------------ modes
func current_mode() -> Mode:
	if _free:
		return Mode.FREE
	if session and session.flow == session.Flow.TITLE:
		return Mode.TITLE_ORBIT
	return Mode.CHASE if driving else Mode.FOLLOW


## Stable string for the frozen read model and HUD.
func mode_name() -> String:
	match current_mode():
		Mode.FREE: return "free"
		Mode.TITLE_ORBIT: return "title"
		Mode.CHASE: return "chase"
		_: return "foot"


func is_free() -> bool:
	return _free


func free_camera_hint() -> String:
	if not _free:
		return ""
	return "FREE CAMERA  ·  WASD move  ·  Q/E rise + fall  ·  SHIFT boost  ·  mouse look  ·  F / ESC return"


func _on_session_changed(_event: Dictionary) -> void:
	# Restart, finish or an external modal clear must never strand the free camera.
	if _free and (session.flow != session.Flow.PLAYING or not session.paused):
		_finish_free(false)


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	if target == null:
		return
	var step := minf(delta, 0.05)
	if _free:
		_free_step(delta)
		return
	if session and session.paused:
		return
	_follow_step(step, current_mode())


func _follow_step(step: float, mode: Mode) -> void:
	if mode != _last_mode:
		_last_mode = mode
		# Each mode remembers its own zoom; switching eases over, never snaps.
		distance_target = _chase_distance if mode == Mode.CHASE else _foot_distance
	var manual := false
	if mode != Mode.TITLE_ORBIT:
		manual = _read_pad_look(step)
	# Per-mode pitch range: ease the pose into it instead of snapping.
	var min_pitch := chase_pitch_min if mode == Mode.CHASE else foot_pitch_min
	var max_pitch := chase_pitch_max if mode == Mode.CHASE else foot_pitch_max
	var wanted_pitch := clampf(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	pitch = move_toward(pitch, wanted_pitch, deg_to_rad(pitch_ease) * step)
	var min_dist := chase_dist_min if mode == Mode.CHASE else foot_dist_min
	var max_dist := chase_dist_max if mode == Mode.CHASE else foot_dist_max
	distance_target = clampf(distance_target, min_dist, max_dist)
	distance = lerpf(distance, distance_target, clampf(transition_rate * step, 0.0, 1.0))

	if _recenter_pending and mode != Mode.TITLE_ORBIT:
		_recenter_pending = false
		_recenter_active = true
		look_idle = 0.0
	if mode == Mode.TITLE_ORBIT:
		yaw += 0.11 * step
	elif _recenter_active:
		var w := clampf(recenter_rate * step, 0.0, 1.0)
		yaw = lerp_angle(yaw, _recenter_yaw(), w)
		pitch = lerpf(pitch, _recenter_pitch(), w)
		look_idle = recenter_grace
		if absf(angle_difference(yaw, _recenter_yaw())) < 0.01 and absf(pitch - _recenter_pitch()) < 0.01:
			_recenter_active = false
	elif mode == Mode.CHASE and not manual:
		look_idle += step
		if look_idle > recenter_grace:
			var w := clampf(recenter_rate * step, 0.0, 1.0)
			yaw = lerp_angle(yaw, target.rotation.y, w)
			pitch = lerpf(pitch, deg_to_rad(chase_pitch_default), w)

	var pivot := _sweep_pivot()
	var dir := dir_from_angles(yaw, pitch)
	allowed_boom = _sweep_boom(pivot, dir, distance)
	var wanted_boom := minf(distance, allowed_boom)
	if wanted_boom < boom:
		boom = wanted_boom
	else:
		boom = minf(move_toward(boom, wanted_boom, extend_rate * step), allowed_boom)
	_finish_pose(pivot + dir * boom, pivot, mode, step)


func _free_step(delta: float) -> void:
	_add_free_look_from_pad(delta)
	var vec := Input.get_vector("free_left", "free_right", "free_forward", "free_back")
	var rise := Input.get_axis("free_down", "free_up")
	var look := dir_from_angles(_free_yaw, _free_pitch)
	var flat_vec := Vector3(look.x, 0.0, look.z)
	var flat := flat_vec.normalized() if flat_vec.length() > 0.001 else Vector3.FORWARD
	var sideways := look.cross(Vector3.UP)
	var right := sideways.normalized() if sideways.length() > 0.001 else Vector3.RIGHT
	var move := flat * -vec.y + right * vec.x + Vector3.UP * rise
	if move.length() > 0.001:
		var speed := free_speed * (free_boost if Input.is_action_pressed("free_boost") else 1.0)
		_free_position += move.normalized() * speed * delta
	var extent := free_extent
	_free_position.x = clampf(_free_position.x, -extent, extent)
	_free_position.z = clampf(_free_position.z, -extent, extent)
	_free_position.y = clampf(_free_position.y, free_floor, free_ceiling)
	global_position = _free_position
	look_at(_free_position + look, Vector3.UP)


func _finish_pose(final: Vector3, pivot: Vector3, mode: Mode, step: float) -> void:
	if _ready_first:
		global_position = final
		_ready_first = false
		_blend_t = 0.0
	elif _blend_t > 0.0:
		_blend_t = maxf(_blend_t - step, 0.0)
		var w := clampf(_blend_t / maxf(free_return_time, 0.01), 0.0, 1.0)
		global_position = _blend_from.lerp(final, 1.0 - w)
	else:
		global_position = final
	var focus := pivot
	if mode == Mode.CHASE:
		focus += Vector3(sin(target.rotation.y), 0, cos(target.rotation.y)) * 2.6
	if global_position.distance_to(focus) > 0.05:
		look_at(focus, Vector3.UP)
	_update_occlusion_fade(mode)


## Boom elevation direction for a yaw/pitch pair. The free camera reuses the
## same vector as its look direction.
static func dir_from_angles(a_yaw: float, a_pitch: float) -> Vector3:
	return Vector3(sin(a_yaw) * cos(a_pitch), sin(a_pitch), cos(a_yaw) * cos(a_pitch))


func _sweep_pivot() -> Vector3:
	# Head-height focus; the sweep origin keeps the Phase 03 +1.5 m contract.
	return target.global_position + Vector3(0, 1.5, 0)


## Sphere-swept cap on the boom. Returns metres between the mode's minimum and
## `want`. The sweep excludes the followed body only; walls, props and the other
## actor stay solid. A pivot that already sits inside geometry collapses to the
## minimum boom instead of exploding; clearing walls cost no length at all.
## Pull-in is immediate, extension eases in _follow_step.
func _sweep_boom(pivot: Vector3, dir: Vector3, want: float) -> float:
	var min_boom := chase_min_boom if driving else foot_min_boom
	var space := get_world_3d().direct_space_state
	if space == null:
		return want
	var shape := SphereShape3D.new()
	shape.radius = collision_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Layers.WORLD | Layers.VEHICLE
	query.margin = 0.0
	query.transform = Transform3D(Basis(), pivot)
	query.motion = dir * want
	if target is CollisionObject3D:
		var excluded: Array[RID] = [(target as CollisionObject3D).get_rid()]
		query.exclude = excluded
	# cast_motion ignores shapes that start overlapped; test the start explicitly.
	if not space.intersect_shape(query, 1).is_empty():
		return min_boom
	var result := space.cast_motion(query)
	var safe := 1.0
	if result.size() >= 2:
		safe = result[0]
	if safe >= 1.0:
		return want
	return clampf(want * safe - collision_skin, min_boom, want)


# ------------------------------------------------------------------ look input
func _read_pad_look(step: float) -> bool:
	var pad := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if pad.length() < 0.12:
		return false
	var flip := -1.0 if invert_y else 1.0
	_add_look(-pad.x * pad_sensitivity * step, pad.y * pad_sensitivity * step * flip)
	return true


## Mouse/drag look in pixels. Mouse right looks right, mouse up looks up.
func apply_look(pixels: Vector2) -> void:
	var flip := -1.0 if invert_y else 1.0
	_add_look(-pixels.x * mouse_sensitivity, pixels.y * mouse_sensitivity * flip)


func _add_look(dyaw: float, dpitch: float) -> void:
	look_idle = 0.0
	_recenter_active = false
	yaw = wrapf(yaw + dyaw, -PI, PI)
	pitch += dpitch


func _add_free_look(dyaw: float, dlook_pitch: float) -> void:
	_free_yaw = wrapf(_free_yaw + dyaw, -PI, PI)
	_free_pitch = clampf(_free_pitch + dlook_pitch, -deg_to_rad(89.0), deg_to_rad(89.0))


func _add_free_look_from_pad(step: float) -> void:
	var pad := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if pad.length() < 0.12:
		return
	var flip := -1.0 if invert_y else 1.0
	_add_free_look(-pad.x * pad_sensitivity * step, -pad.y * pad_sensitivity * step * flip)


## Wheel/gamepad zoom. Positive notches zoom in; ignored by the free camera.
func zoom_by(notches: float) -> void:
	if _free:
		return
	var min_dist := chase_dist_min if driving else foot_dist_min
	var max_dist := chase_dist_max if driving else foot_dist_max
	distance_target = clampf(distance_target - notches * zoom_step, min_dist, max_dist)
	if driving:
		_chase_distance = distance_target
	else:
		_foot_distance = distance_target


func recenter_now() -> void:
	_recenter_pending = true


func _recenter_yaw() -> float:
	if driving:
		return target.rotation.y
	return target.rotation.y + deg_to_rad(foot_recenter_offset)


func _recenter_pitch() -> float:
	return deg_to_rad(chase_pitch_default if driving else foot_pitch_default)


# ------------------------------------------------------------------ free camera
## Enter the independent free camera. Freezes gameplay through the session's
## dedicated modal reason; rejected if another modal already owns pause.
func enter_free() -> bool:
	if _free or session == null or target == null:
		return false
	if session.flow != session.Flow.PLAYING or session.paused:
		return false
	if not session.open_modal(FREE_MODAL):
		return false
	_saved = {
		"target": target,
		"driving": driving,
		"yaw": yaw,
		"pitch": pitch,
		"distance": _chase_distance if driving else _foot_distance,
		"mouse": Input.mouse_mode,
	}
	var forward := -global_transform.basis.z
	_free_pitch = asin(clampf(forward.y, -1.0, 1.0))
	_free_yaw = atan2(forward.x, forward.z)
	_free_position = global_position
	_blend_t = 0.0
	_free = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


func exit_free() -> bool:
	if not _free:
		return false
	_finish_free(true)
	return true


func toggle_free() -> bool:
	if _free:
		return exit_free()
	return enter_free()


func _finish_free(close_modal: bool) -> void:
	if not _free:
		return
	_free = false
	if _saved.has("target"):
		target = _saved.target
		driving = _saved.driving
		yaw = _saved.yaw
		pitch = _saved.pitch
		distance_target = _saved.distance
		_blend_from = global_position
		_blend_t = free_return_time
	look_idle = 0.0
	_saved = {}
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if close_modal and session:
		session.close_modal(FREE_MODAL)


# ------------------------------------------------------------------ occlusion aid
func _update_occlusion_fade(mode: Mode) -> void:
	var want := 0.0
	if mode == Mode.FOLLOW and target != null and boom < occlude_fade_start:
		var span := maxf(occlude_fade_start - occlude_fade_end, 0.01)
		want = occlude_fade_max * clampf((occlude_fade_start - boom) / span, 0.0, 1.0)
	_apply_fade(want)


func _apply_fade(value: float) -> void:
	if target != _fade_target or (_fade_nodes.is_empty() and target != null):
		for node in _fade_nodes:
			if is_instance_valid(node):
				node.transparency = 0.0
		_fade_nodes.clear()
		_fade_target = target
		if target:
			for node in target.find_children("*", "GeometryInstance3D", true, false):
				_fade_nodes.append(node as GeometryInstance3D)
	if is_equal_approx(value, _fade_value):
		return
	_fade_value = value
	for node in _fade_nodes:
		if is_instance_valid(node):
			node.transparency = value


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if _free:
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			var flip := -1.0 if invert_y else 1.0
			_add_free_look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity * flip)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cam_zoom_in") or event.is_action_pressed("cam_zoom_out"):
			# The free camera has no zoom gesture yet; consume so it cannot leak.
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cam_free"):
			exit_free()
			get_viewport().set_input_as_handled()
		return
	# Any other modal owns the camera: consume nothing, move nothing.
	if session.paused or session.flow != session.Flow.PLAYING:
		_dragging = false
		return
	if event.is_action_pressed("cam_free"):
		if toggle_free():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cam_zoom_in"):
		zoom_by(1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_zoom_out"):
		zoom_by(-1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_recenter"):
		recenter_now()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_orbit"):
		_dragging = true
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif _dragging and event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		var released := event as InputEventMouseButton
		if _orbit_button() == MOUSE_BUTTON_NONE or released.button_index == _orbit_button():
			_dragging = false
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _dragging and event is InputEventMouseMotion:
		apply_look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()


func _orbit_button() -> int:
	for ev in InputMap.action_get_events("cam_orbit"):
		if ev is InputEventMouseButton:
			return (ev as InputEventMouseButton).button_index
	return MOUSE_BUTTON_NONE


func _exit_tree() -> void:
	# Scene teardown while the free camera owns a captured mouse must not strand it.
	if _free and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
