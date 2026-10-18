extends SceneTree
## Cross-process settings persistence probe for the suite. Preferences are only
## proven saved when a *different* process reads them back, so the suite runs
## this three times against one probe path (never user://settings.cfg):
##   --mode=write  store volumes, video, camera, text and a remap
##   --mode=read   load them in a fresh process and verify values + InputMap
##   --mode=clean  delete the probe file
## godot --headless --path . --script tools/settings_probe.gd -- --mode=write \
##   --settings=user://phase05-probe.cfg
const SettingsService = preload("res://scripts/services/settings_service.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")

var mode := ""
var path := "user://phase05-probe.cfg"
var failures := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.substr("--mode=".length())
		elif arg.begins_with("--settings="):
			path = arg.substr("--settings=".length())
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func frame() -> void:
	await process_frame
	await process_frame


func run() -> void:
	match mode:
		"write":
			await write_settings()
		"read":
			await read_settings()
		"clean":
			await clean_settings()
		_:
			check(false, "probe mode was given (write, read or clean)")
	print("SETTINGS PROBE %s: %d failures" % [mode.to_upper(), failures])
	quit(1 if failures > 0 else 0)


func _service(autosave: bool) -> Node:
	var service := SettingsService.new()
	root.add_child(service)
	service.configure(path, autosave)
	service.load_settings()
	return service


func write_settings() -> void:
	var service := _service(true)
	check(is_equal_approx(float(service.value("audio/master")), 1.0), "the probe path starts from defaults")
	service.set_value("audio/sfx", 0.35)
	service.set_value("audio/music", 0.25)
	service.set_value("video/ui_scale", 1.25)
	service.set_value("video/shadows", false)
	service.set_value("camera/invert_y", true)
	service.set_value("camera/sensitivity", 1.75)
	service.set_value("text/speed", 1.5)
	check(service.set_binding("interact", _event(KEY_J)) == "", "the probe remap is accepted")
	check(FileAccess.file_exists(path), "the probe settings file exists after saving")
	service.queue_free()
	await frame()
	print("PROBE WRITE OK sfx=0.35 music=0.25 ui=1.25 shadow=off invert=on sens=1.75 speed=1.5 interact=J")


func read_settings() -> void:
	check(FileAccess.file_exists(path), "the probe settings file survived the process boundary")
	# Touch nothing: load_settings() must apply the stored file on its own.
	var service := _service(false)
	check(is_equal_approx(float(service.value("audio/sfx")), 0.35), "a saved volume loads in a new process")
	check(is_equal_approx(float(service.value("audio/music")), 0.25), "a second saved volume loads too")
	check(is_equal_approx(float(service.value("video/ui_scale")), 1.25), "a saved UI scale loads")
	check(is_equal_approx(game_window_factor(), 1.25), "the loaded UI scale reached the window")
	check(service.value("video/shadows") == false, "a saved toggle loads")
	check(service.value("camera/invert_y") == true, "a saved camera preference loads")
	check(is_equal_approx(float(service.value("camera/sensitivity")), 1.75), "a saved sensitivity loads")
	check(is_equal_approx(float(service.value("text/speed")), 1.5), "a saved text speed loads")
	check(InputBindings.prompt("interact") == "J", "a saved remap reached InputMap")
	check(service.binding_label("interact") == "J", "the loaded remap is reported to the UI")
	check(is_equal_approx(float(service.value("audio/master")), 1.0), "untouched keys keep their defaults")
	check(InputBindings.prompt("move_forward") == "W", "untouched actions keep their shipped keys")
	service.queue_free()
	await frame()
	print("PROBE READ OK interact=J ui=1.25 sfx=0.35 music=0.25")


func clean_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not FileAccess.file_exists(path), "the probe settings file is removed")
	print("PROBE CLEAN OK")


func game_window_factor() -> float:
	return root.content_scale_factor


func _event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
