extends SceneTree
## One-shot project configuration: input map, main scene, window and the capture
## autoload. Run headless:  godot --headless --path . --script tools/setup_project.gd
func _initialize() -> void:
	var acts := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E],
		"honk": [KEY_H],
		"handbrake": [KEY_SPACE],
		"pause": [KEY_ESCAPE],
		"restart": [KEY_R],
		"confirm": [KEY_ENTER, KEY_KP_ENTER],
	}
	for name in acts:
		var events := []
		for key in acts[name]:
			var ev := InputEventKey.new()
			ev.device = -1
			ev.physical_keycode = key
			events.append(ev)
		ProjectSettings.set_setting("input/" + name, {"deadzone": 0.2, "events": events})
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/game.tscn")
	ProjectSettings.set_setting("application/config/name", "Pip the Pizza Boy")
	ProjectSettings.set_setting("application/config/description",
		"Hot pizza, small island, sharp clock. A voxel delivery run on Marinara Way.")
	ProjectSettings.set_setting("autoload/Capture", "*res://tools/capture.gd")
	ProjectSettings.set_setting("display/window/size/viewport_width", 1440)
	ProjectSettings.set_setting("display/window/size/viewport_height", 1080)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1280)
	ProjectSettings.set_setting("display/window/size/window_height_override", 720)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	var err := ProjectSettings.save()
	print("project settings saved, err=", err)
	quit()
