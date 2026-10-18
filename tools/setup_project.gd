extends SceneTree
## One-shot project configuration: input map, main scene, window and the capture
## autoload. Run headless:  godot --headless --path . --script tools/setup_project.gd
## Keys, mouse buttons and gamepad buttons/axes are all declared here so every
## player binding survives regeneration.
func _initialize() -> void:
	var acts := {
		"move_forward": {"keys": [KEY_W, KEY_UP]},
		"move_back": {"keys": [KEY_S, KEY_DOWN]},
		"move_left": {"keys": [KEY_A, KEY_LEFT]},
		"move_right": {"keys": [KEY_D, KEY_RIGHT]},
		"interact": {"keys": [KEY_E]},
		"cargo_cycle": {"keys": [KEY_TAB]},
		"honk": {"keys": [KEY_H]},
		"handbrake": {"keys": [KEY_SPACE]},
		"pause": {"keys": [KEY_ESCAPE]},
		"restart": {"keys": [KEY_R]},
		"confirm": {"keys": [KEY_ENTER, KEY_KP_ENTER]},
		# Camera (Phase 04): right-drag orbits, wheel/shoulders zoom, C/right-stick
		# click recenters, F/Back opens the free camera. Free-camera movement uses
		# its own remappable actions, not the gameplay ones.
		"cam_orbit": {"mouse": [MOUSE_BUTTON_RIGHT]},
		"cam_zoom_in": {"mouse": [MOUSE_BUTTON_WHEEL_UP], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
		"cam_zoom_out": {"mouse": [MOUSE_BUTTON_WHEEL_DOWN], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
		"cam_recenter": {"keys": [KEY_C], "buttons": [JOY_BUTTON_RIGHT_STICK]},
		"cam_free": {"keys": [KEY_F], "buttons": [JOY_BUTTON_BACK]},
		"cam_left": {"axes": [[JOY_AXIS_RIGHT_X, -1.0]]},
		"cam_right": {"axes": [[JOY_AXIS_RIGHT_X, 1.0]]},
		"cam_up": {"axes": [[JOY_AXIS_RIGHT_Y, -1.0]]},
		"cam_down": {"axes": [[JOY_AXIS_RIGHT_Y, 1.0]]},
		"free_forward": {"keys": [KEY_W]},
		"free_back": {"keys": [KEY_S]},
		"free_left": {"keys": [KEY_A]},
		"free_right": {"keys": [KEY_D]},
		"free_up": {"keys": [KEY_Q]},
		"free_down": {"keys": [KEY_CTRL]},
		"free_boost": {"keys": [KEY_SHIFT]},
	}
	for name in acts:
		var spec: Dictionary = acts[name]
		var events := []
		for key in spec.get("keys", []):
			var ev := InputEventKey.new()
			ev.device = -1            # matches any keyboard device (Phase 01 fix)
			ev.physical_keycode = key
			events.append(ev)
		for button in spec.get("mouse", []):
			var ev := InputEventMouseButton.new()
			ev.device = -1
			ev.button_index = button
			events.append(ev)
		for button in spec.get("buttons", []):
			var ev := InputEventJoypadButton.new()
			ev.device = -1
			ev.button_index = button
			events.append(ev)
		for axis in spec.get("axes", []):
			var ev := InputEventJoypadMotion.new()
			ev.device = -1
			ev.axis = axis[0]
			ev.axis_value = axis[1]
			events.append(ev)
		ProjectSettings.set_setting("input/" + name, {"deadzone": 0.2, "events": events})
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/game.tscn")
	ProjectSettings.set_setting("application/config/name", "Pip the Pizza Boy")
	ProjectSettings.set_setting("application/config/description",
		"Hot pizza, small island, sharp clock. A voxel delivery run on Marinara Way.")
	ProjectSettings.set_setting("autoload/Capture", "*res://tools/capture.gd")
	ProjectSettings.set_setting("display/window/size/viewport_width", 1920)
	ProjectSettings.set_setting("display/window/size/viewport_height", 1080)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1920)
	ProjectSettings.set_setting("display/window/size/window_height_override", 1080)
	# Reference machine is an RTX 3050 6 GB laptop (95 W): Forward+ is the
	# target renderer, so SSAO, glow, soft shadows and lightmaps are available.
	# The Options screen's QUALITY PRESET drives MSAA/AA, shadows and glow at
	# runtime; these are the shipped starting values.
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "forward_plus")
	ProjectSettings.set_setting("rendering/renderer/rendering_method.mobile", "forward_plus")
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 3)
	var err := ProjectSettings.save()
	print("project settings saved, err=", err)
	quit()
