extends SceneTree
## Phase 04 camera acceptance: bindings, look/zoom clamps, collision boom,
## free-camera freeze/restore, modal gating and title independence.
## godot --headless --audio-driver Dummy --path . --script tools/phase04_checks.gd
const Fixture = preload("res://tools/dev_fixture.gd")
const Layers = preload("res://scripts/collision_layers.gd")
var failures := 0
var checks := 0
var game: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func frame() -> void:
	await physics_frame
	await process_frame
	await process_frame


func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func create_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Camera-specific checks use canonical values; do not inherit the developer's
	# persisted sensitivity or recenter preferences from user://settings.cfg.
	game.camera.apply_preferences(1.0, false, true, false)
	await frame()
	game.set_order_seed(20261018)


func destroy_game() -> void:
	game.queue_free()
	game = null
	await frame()
	await create_timer(0.15).timeout


## First key/mouse event of an action, so checks drive the same path as players.
func action_event(name: String) -> InputEvent:
	for ev in InputMap.action_get_events(name):
		if ev is InputEventKey:
			var key := InputEventKey.new()
			key.physical_keycode = (ev as InputEventKey).physical_keycode
			return key
		elif ev is InputEventMouseButton:
			var button := InputEventMouseButton.new()
			button.button_index = (ev as InputEventMouseButton).button_index
			return button
	return null


func tap(name: String) -> void:
	var event := action_event(name)
	if event == null:
		return
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frame()
	event = action_event(name)
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func hold(name: String, pressed: bool) -> void:
	var event := action_event(name)
	if event == null:
		return
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func move_mouse(dx: float, dy: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640, 360)
	motion.relative = Vector2(dx, dy)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func box_at(pos: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = Layers.WORLD
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	return body


func pip_fade() -> float:
	for node in game.pip.find_children("*", "GeometryInstance3D", true, false):
		return (node as GeometryInstance3D).transparency
	return 0.0


func converge_yaw(target_yaw: float, limit: int) -> bool:
	for i in range(limit):
		await physics_frame
		if absf(angle_difference(game.camera.yaw, target_yaw)) < 0.05:
			return true
	return false


func bindings() -> void:
	var right_drag := false
	for ev in InputMap.action_get_events("cam_orbit"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			right_drag = true
	check(right_drag, "cam_orbit is bound to right-mouse drag")
	var wheel_in := false
	for ev in InputMap.action_get_events("cam_zoom_in"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel_in = true
	var wheel_out := false
	for ev in InputMap.action_get_events("cam_zoom_out"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_out = true
	check(wheel_in and wheel_out, "cam_zoom_in/out use the wheel notches")
	var recenter := false
	for ev in InputMap.action_get_events("cam_recenter"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_C:
			recenter = true
	check(recenter, "cam_recenter is bound to C")
	var free_key := false
	for ev in InputMap.action_get_events("cam_free"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F:
			free_key = true
	check(free_key, "cam_free is bound to F")
	var pad_axes := 0
	for action in ["cam_left", "cam_right", "cam_up", "cam_down"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				var axis := (ev as InputEventJoypadMotion).axis
				if axis == JOY_AXIS_RIGHT_X or axis == JOY_AXIS_RIGHT_Y:
					pad_axes += 1
	check(pad_axes == 4, "gamepad right stick drives camera look")
	var missing: Array[String] = []
	for action in ["free_forward", "free_back", "free_left", "free_right", "free_up", "free_down", "free_boost"]:
		if not InputMap.has_action(action):
			missing.append(action)
	check(missing.is_empty(), "free-camera movement actions exist " + str(missing))
	check(InputMap.has_action("move_forward") and InputMap.has_action("free_forward")
		and InputMap.action_get_events("move_forward") != InputMap.action_get_events("free_forward"),
		"free-camera movement is remappable separately from gameplay")


func run() -> void:
	InputMap.load_from_project_settings()
	bindings()
	await create_game()
	var camera: Camera3D = game.camera
	check(camera.mode_name() == "title" and camera.current_mode() == camera.Mode.TITLE_ORBIT and camera.orbit,
		"title screen starts in the independent orbit")
	# Title orbit must ignore player look input entirely (0.77 rad drag is not applied).
	var title_yaw: float = camera.yaw
	hold("cam_orbit", true)
	move_mouse(240, 0)
	hold("cam_orbit", false)
	await frames(3)
	check(not camera._dragging and absf(angle_difference(camera.yaw, title_yaw)) < 0.2
		and absf(angle_difference(camera.yaw, title_yaw)) > 0.0,
		"title orbit is independent of player camera input")
	check(not camera.enter_free(), "free camera cannot open before a shift starts")

	game.start_shift()
	# Camera clock assertions need a live route timer. Prep and receipt now happen
	# before freshness begins, so put the service into that state explicitly here.
	game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())
	game.orders.pickup()
	await frames(2)
	check(camera.mode_name() == "foot" and camera.target == game.pip, "shift starts on foot with the follow camera")
	check(game.get_snapshot().camera_mode == "foot" and game.get_snapshot().camera_hint == "",
		"snapshot publishes camera mode without a hint while playing")

	# --- look and invert
	var yaw0: float = camera.yaw
	camera.apply_look(Vector2(120, 0))
	check(camera.yaw < yaw0, "mouse right looks right")
	var pitch0: float = camera.pitch
	camera.invert_y = false
	camera.apply_look(Vector2(0, -60))
	check(camera.pitch < pitch0, "mouse up looks up by default")
	camera.invert_y = true
	pitch0 = camera.pitch
	camera.apply_look(Vector2(0, -60))
	check(camera.pitch > pitch0, "inverted Y flips the vertical look")
	camera.invert_y = false

	# --- zoom clamps and per-mode memory
	camera.zoom_by(50.0)
	check(is_equal_approx(camera.distance_target, game.balance.cam_foot_dist_min), "wheel zoom clamps at the foot minimum")
	camera.zoom_by(-80.0)
	check(is_equal_approx(camera.distance_target, game.balance.cam_foot_dist_max), "wheel zoom clamps at the foot maximum")

	# --- recenter eases behind the followed actor
	camera.apply_look(Vector2(240, 0))
	camera.recenter_now()
	var foot_target: float = game.pip.rotation.y + deg_to_rad(game.balance.cam_foot_recenter_offset)
	check(await converge_yaw(foot_target, 300), "C recenter eases the foot camera behind Pip")

	# --- collision boom: a wall between pivot and the boom endpoint
	Fixture.place(game, "pip", game.world.player_spawn.global_position + Vector3(0, 0.2, 0))
	camera.zoom_by(-80.0)
	await frames(40)
	var settled_boom: float = camera.boom
	check(settled_boom > game.balance.cam_foot_min_boom + 0.5, "spawn area gives the boom room, actual=%.2f" % settled_boom)
	var dir: Vector3 = camera.dir_from_angles(camera.yaw, camera.pitch)
	var pivot: Vector3 = game.pip.global_position + Vector3(0, 1.5, 0)
	var wall := box_at(pivot + dir * settled_boom * 0.6, Vector3(6, 6, 1.0), atan2(dir.x, dir.z))
	await frames(5)
	check(camera.allowed_boom < settled_boom * 0.8 and camera.boom <= camera.allowed_boom + 0.01,
		"wall clamps the boom, allowed=%.2f boom=%.2f settled=%.2f" % [camera.allowed_boom, camera.boom, settled_boom])
	check((camera.global_position - pivot).length() <= camera.allowed_boom + 0.05,
		"final smoothed position never passes the clamped endpoint")
	var wall_boom: float = camera.boom
	wall.queue_free()
	await frames(90)
	check(camera.boom > wall_boom + 1.0 and camera.boom <= camera.allowed_boom + 0.01,
		"boom eases back out when the wall is gone, boom=%.2f" % camera.boom)

	# --- starting inside geometry: no explosion, minimum boom, occlusion aid
	# One frame only: the CharacterBody depenetration pushes Pip out of the shell
	# after a handful of ticks, and the pivot rides along with him.
	var shell := box_at(pivot, Vector3(4, 4, 4))
	await frames(1)
	check(camera.allowed_boom <= game.balance.cam_foot_min_boom + 0.02 and camera.boom <= game.balance.cam_foot_min_boom + 0.02,
		"geometry around the pivot clamps to the minimum boom")
	check(is_finite(camera.global_position.x) and is_finite(camera.global_position.y) and is_finite(camera.global_position.z),
		"camera stays finite when starting inside geometry")
	check(pip_fade() > 0.2, "occluded Pip gets the subtle see-through aid")
	shell.queue_free()
	await frames(120)
	check(pip_fade() == 0.0, "occlusion aid clears once the view opens up")

	# --- modals own the camera; only the free camera keeps controls
	game.open_modal(&"map")
	var paused_yaw: float = camera.yaw
	var paused_zoom: float = camera.distance_target
	hold("cam_zoom_in", true)
	hold("cam_zoom_in", false)
	move_mouse(300, 0)
	await frames(3)
	check(is_equal_approx(camera.distance_target, paused_zoom), "menu/dialogue focus consumes camera zoom first")
	check(absf(angle_difference(camera.yaw, paused_yaw)) < 0.001, "menu/dialogue focus consumes camera look first")
	check(not camera.enter_free(), "free camera refuses to stack on another modal")
	game.close_modal(&"map")
	await frames(2)

	# --- free camera freezes the world and restores state
	var timer0: float = game.get_snapshot().timer
	var van_pos: Vector3 = game.van.global_position
	check(camera.enter_free(), "free camera opens during play")
	check(camera.mode_name() == "free" and game.paused and paused, "free camera pauses gameplay through its own modal")
	check(game.session.reasons() == [&"free_camera"], "free camera owns exactly one pause reason")
	camera.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	camera.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(camera.is_free() and game.paused, "free camera survives a focus round trip")
	var view = game.get_snapshot()
	check(view.camera_mode == "free" and view.camera_hint.contains("FREE CAMERA"), "snapshot publishes the free-camera mode and hint")
	await frame()
	check(game.hud._camera_hint.visible and game.hud._camera_hint.text == view.camera_hint,
		"HUD shows the free-camera mode label and controls")
	hold("free_forward", true)
	hold("free_boost", true)
	hold("move_forward", true)
	var free_start: Vector3 = camera.global_position
	await frames(30)
	var free_moved: float = camera.global_position.distance_to(free_start)
	hold("free_forward", false)
	hold("free_boost", false)
	hold("move_forward", false)
	check(free_moved > 1.0, "free camera flies with its own controls, moved=%.2f" % free_moved)
	check(game.van.global_position == van_pos, "camera WASD never moves the van")
	await frames(10)
	check(game.get_snapshot().timer == timer0, "deadlines stay frozen inside the free camera")
	var zoom_before: float = camera.distance_target
	camera.zoom_by(2.0)
	check(is_equal_approx(camera.distance_target, zoom_before), "free camera leaves follow zoom untouched")
	check(camera.exit_free() and not game.paused and not paused, "returning restores play and unpauses")
	check(camera.mode_name() == "foot" and game.get_snapshot().camera_hint == "", "hint clears after returning")
	await frames(12)
	check(game.get_snapshot().timer < timer0, "deadline clock resumes after the free camera closes")

	# --- F toggles, Esc is cancel/back
	await tap("cam_free")
	check(camera.is_free(), "F opens the free camera")
	await tap("pause")
	check(not camera.is_free() and not game.paused and game.is_shift_active(),
		"Esc returns from the free camera instead of stacking pause")

	# --- losing window focus mid-drag drops the drag and the stray motion
	hold("cam_orbit", true)
	await frame()
	check(camera._dragging, "right-drag starts the camera drag")
	camera.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var drag_yaw: float = camera.yaw
	move_mouse(200, 0)
	await frames(2)
	check(not camera._dragging and absf(angle_difference(camera.yaw, drag_yaw)) < 0.001,
		"focus loss mid-drag drops the drag and ignores stray mouse motion")
	hold("cam_orbit", false)
	camera.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)

	# --- free camera while driving restores the chase pose
	Fixture.place(game, "pip", game.van.global_position + game.van.global_basis.x * 2.0)
	game.interact()
	await frames(4)
	check(game.driving and camera.mode_name() == "chase" and camera.target == game.van, "entering the van hands over the chase camera")
	camera.apply_look(Vector2(300, 0))
	check(absf(angle_difference(camera.yaw, game.van.rotation.y)) > 0.3, "manual driving look suspends automatic recentering")
	await frames(30)
	check(absf(angle_difference(camera.yaw, game.van.rotation.y)) > 0.2, "recentering waits for the idle grace")
	var grace: float = camera.recenter_grace
	camera.recenter_grace = 0.05
	check(await converge_yaw(game.van.rotation.y, 300), "chase camera recenters behind the van after the grace")
	camera.recenter_grace = grace
	check(camera.enter_free(), "free camera opens while driving")
	hold("free_left", true)
	await frames(20)
	hold("free_left", false)
	var van_driving: Vector3 = game.van.global_position
	await tap("cam_free")
	check(not camera.is_free() and game.driving and camera.target == game.van and camera.mode_name() == "chase",
		"F returning while driving restores the van chase pose")
	await frames(4)
	check(absf(game.van.global_position.x - van_driving.x) < 0.001 and absf(game.van.global_position.z - van_driving.z) < 0.001,
		"returning never moves the van")
	check(game.get_snapshot().actor_mode == "driving", "actor mode survives the free-camera round trip")

	# --- restart while the free camera is open cannot strand it
	check(camera.enter_free(), "free camera opens before the restart")
	game.restart()
	check(not camera.is_free() and not game.paused, "restart closes the free camera and unpauses")
	check(camera.mode_name() == "title" and camera.target == game.pip and not camera.driving, "restart restores the title orbit target")
	check(absf(angle_difference(camera.yaw, game.pip.rotation.y + deg_to_rad(140.0))) < 0.001, "restart restores the spawn orbit yaw")
	await destroy_game()
	print("PHASE 04: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
