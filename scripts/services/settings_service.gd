extends Node
## user://settings.cfg owner: audio, video, camera, text and input preferences.
## Separate from campaign saves; no order/session/money state lives here.
## Applies global systems itself (audio buses, window, UI scale, shadow filter,
## InputMap) and emits `changed` for scene-owned pieces (camera pose, sun).

signal changed(key: String)
signal input_changed()

const InputBindings = preload("res://scripts/services/input_bindings.gd")

const VERSION := 1
const DEFAULT_PATH := "user://settings.cfg"
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SHADOW_DISTANCES := [60.0, 95.0, 140.0]
const SHADOW_ATLAS := [2048, 4096, 4096]
const FRAME_CAPS := [60, 120, 0]

## Macro presets for the reference machine (RTX 3050 6 GB laptop). Selecting one
## writes the fine-grained video keys below through `set_value`, so a preset is
## never a decorative switch: each value it sets has its own row and its own
## apply path.
const QUALITY_PRESETS := {
	"low": {"video/msaa": 0, "video/ssao": 0, "video/glow": false,
		"video/shadows": true, "video/shadow_quality": 0, "video/frame_cap": 60},
	"medium": {"video/msaa": 1, "video/ssao": 1, "video/glow": true,
		"video/shadows": true, "video/shadow_quality": 1, "video/frame_cap": 60},
	"high": {"video/msaa": 2, "video/ssao": 2, "video/glow": true,
		"video/shadows": true, "video/shadow_quality": 2, "video/frame_cap": 60},
}

## Actions the controls screen can remap; every name is generated into InputMap
## by tools/setup_project.gd and survives regeneration.
const REMAPPABLE: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right",
	"interact", "handbrake", "horn", "confirm",
	"cam_orbit", "cam_recenter", "cam_free",
	"free_up", "free_down", "free_boost",
]

const DEFAULTS := {
	"audio/master": 1.0,
	"audio/music": 0.8,
	"audio/sfx": 1.0,
	"audio/ambience": 0.8,
	"video/quality": "high",
	"video/window_mode": 0,
	"video/window_preset": 2,
	"video/ui_scale": 1.0,
	"video/shadows": true,
	"video/shadow_quality": 2,
	"video/msaa": 2,
	"video/ssao": 2,
	"video/glow": true,
	"video/frame_cap": 60,
	"camera/sensitivity": 1.0,
	"camera/invert_y": false,
	"camera/recenter": true,
	"camera/reduced_motion": false,
	"text/subtitles": true,
	"text/speed": 1.0,
}

## Order, labels and widget kinds for the options screen. `needs_window` rows
## are disabled with an explanation where no real window exists (headless).
const SPEC := [
	{"key": "audio/master", "label": "MASTER VOLUME", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	{"key": "audio/music", "label": "MUSIC VOLUME", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	{"key": "audio/sfx", "label": "SOUND EFFECTS", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	{"key": "audio/ambience", "label": "AMBIENCE", "kind": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "percent": true},
	{"key": "video/quality", "label": "QUALITY PRESET", "kind": "choice", "options": ["LOW", "MEDIUM", "HIGH"], "values": ["low", "medium", "high"]},
	{"key": "video/window_mode", "label": "WINDOW MODE", "kind": "choice", "options": ["WINDOWED", "FULLSCREEN"], "values": [0, 1], "needs_window": true},
	{"key": "video/window_preset", "label": "WINDOW SIZE", "kind": "choice", "options": ["1280 × 720", "1600 × 900", "1920 × 1080"], "values": [0, 1, 2], "needs_window": true},
	{"key": "video/ui_scale", "label": "UI SCALE", "kind": "choice", "options": ["85%", "100%", "125%", "150%"], "values": [0.85, 1.0, 1.25, 1.5]},
	{"key": "video/shadows", "label": "SHADOWS", "kind": "toggle"},
	{"key": "video/shadow_quality", "label": "SHADOW QUALITY", "kind": "choice", "options": ["LOW", "MEDIUM", "HIGH"], "values": [0, 1, 2]},
	{"key": "video/msaa", "label": "ANTI-ALIASING", "kind": "choice", "options": ["OFF", "2× MSAA", "4× MSAA"], "values": [0, 1, 2]},
	{"key": "video/ssao", "label": "AMBIENT OCCLUSION", "kind": "choice", "options": ["OFF", "LOW", "HIGH"], "values": [0, 1, 2]},
	{"key": "video/glow", "label": "GLOW", "kind": "toggle"},
	{"key": "video/frame_cap", "label": "FRAME CAP", "kind": "choice", "options": ["60 FPS", "120 FPS", "UNLIMITED"], "values": [60, 120, 0]},
	{"key": "camera/sensitivity", "label": "CAMERA SENSITIVITY", "kind": "slider", "min": 0.25, "max": 3.0, "step": 0.05, "percent": true},
	{"key": "camera/invert_y", "label": "INVERT CAMERA Y", "kind": "toggle"},
	{"key": "camera/recenter", "label": "DRIVING AUTO-RECENTER", "kind": "toggle"},
	{"key": "camera/reduced_motion", "label": "REDUCED CAMERA MOTION", "kind": "toggle"},
	{"key": "text/subtitles", "label": "SUBTITLES", "kind": "toggle"},
	{"key": "text/speed", "label": "TEXT SPEED", "kind": "choice", "options": ["75%", "100%", "150%", "200%"], "values": [0.75, 1.0, 1.5, 2.0]},
]

# Captured once per process: the pristine project.godot InputMap before any
# user remap is applied, so resetting to defaults is always possible.
static var _factory_events := {}

var path := DEFAULT_PATH
var autosave := true
var values := {}
var bindings := {}
var _loaded := false


func configure(new_path := DEFAULT_PATH, save_automatically := true) -> void:
	path = new_path
	autosave = save_automatically
	if _factory_events.is_empty():
		_factory_events = InputBindings.capture_all(REMAPPABLE)
	for key in DEFAULTS:
		values[key] = DEFAULTS[key]
	bindings = _default_bindings()


func _default_bindings() -> Dictionary:
	var out := {}
	for action in REMAPPABLE:
		var list: Array = []
		for event in _factory_events.get(action, []):
			if event is InputEvent:
				list.append(InputBindings.serialize(event))
		out[action] = list
	return out


## Read user://settings.cfg, validate every stored value and apply the result.
## A corrupt or partial file falls back to defaults key by key.
func load_settings() -> void:
	configure(path, autosave)
	var file := ConfigFile.new()
	if file.load(path) == OK:
		for key: String in DEFAULTS:
			var parts: PackedStringArray = key.split("/")
			if file.has_section_key(parts[0], parts[1]):
				values[key] = _sanitize(key, file.get_value(parts[0], parts[1]))
		var stored: Variant = null
		if file.has_section_key("input", "bindings"):
			stored = file.get_value("input", "bindings")
		if typeof(stored) == TYPE_DICTIONARY:
			for action in REMAPPABLE:
				if stored.has(action) and typeof(stored[action]) == TYPE_ARRAY and not stored[action].is_empty():
					bindings[action] = stored[action]
	_loaded = true
	apply_all()
	changed.emit("")


func save() -> bool:
	var file := ConfigFile.new()
	file.set_value("meta", "version", VERSION)
	for key: String in DEFAULTS:
		var parts: PackedStringArray = key.split("/")
		file.set_value(parts[0], parts[1], values[key])
	file.set_value("input", "bindings", bindings.duplicate(true))
	return file.save(path) == OK


## Stored preference value (never Object.get).
func value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func is_default(key: String) -> bool:
	return value(key) == DEFAULTS.get(key)


static func window_size(index: int) -> Vector2i:
	return WINDOW_SIZES[clampi(index, 0, WINDOW_SIZES.size() - 1)]


## Set + apply + persist. Returns true when the stored value actually changed.
func set_value(key: String, value: Variant, persist := true) -> bool:
	if not DEFAULTS.has(key):
		return false
	var clean: Variant = _sanitize(key, value)
	if values.get(key) == clean:
		return false
	values[key] = clean
	if key == "video/quality":
		_apply_quality_preset(str(clean))
	else:
		_apply(key)
	if persist and autosave:
		save()
	changed.emit(key)
	return true


func reset_to_defaults(persist := true) -> void:
	for key in DEFAULTS:
		values[key] = DEFAULTS[key]
	bindings = _default_bindings()
	apply_all()
	if persist and autosave:
		save()
	changed.emit("")


# ------------------------------------------------------------------ input
func factory_events() -> Dictionary:
	return _factory_events


## Assign one captured event to an action. Returns the conflicting action name,
## or "" on success. The action always keeps at least one event.
func set_binding(action: String, event: InputEvent) -> String:
	if action not in REMAPPABLE or event == null:
		return "invalid"
	var data := InputBindings.serialize(event)
	if data.is_empty():
		return "invalid"
	var clash := InputBindings.conflict(action, event)
	if not clash.is_empty():
		return clash
	bindings[action] = [data]
	_apply_action(action)
	if autosave:
		save()
	input_changed.emit()
	return ""


## Human label for a conflict message ("MOVE FORWARD", "free_up", ...).
static func action_label(action: String) -> String:
	return InputBindings.LABELS.get(action, action.to_upper())


func reset_bindings(persist := true) -> void:
	bindings = _default_bindings()
	for action in REMAPPABLE:
		_apply_action(action)
	if persist and autosave:
		save()
	input_changed.emit()


func binding_label(action: String) -> String:
	return InputBindings.prompt_all(action)


func _apply_action(action: String) -> void:
	InputBindings.apply(bindings, [action], _factory_events)


## Apply once per action, then keep InputMap in sync with the stored set.
func _sync_input() -> void:
	InputBindings.apply(bindings, REMAPPABLE, _factory_events)


# ------------------------------------------------------------------ apply
func apply_all() -> void:
	_apply_audio()
	_apply_window()
	_apply_ui_scale()
	_apply_shadow_quality()
	_apply_msaa()
	_apply_occlusion_quality()
	_apply_frame_cap()
	_sync_input()


func _apply(key: String) -> void:
	if key.begins_with("audio/"):
		_apply_audio()
	elif key.begins_with("video/window"):
		_apply_window()
	elif key == "video/ui_scale":
		_apply_ui_scale()
	elif key == "video/shadow_quality":
		_apply_shadow_quality()
	elif key == "video/msaa":
		_apply_msaa()
	elif key == "video/ssao":
		_apply_occlusion_quality()
	elif key == "video/frame_cap":
		_apply_frame_cap()
	elif key.begins_with("input"):
		_sync_input()
	# video/shadows, video/glow and camera/text keys are applied by Game from
	# `changed`; video/ssao is split (renderer keys here, Environment there);
	# video/quality writes the fine keys above.


static func bus_index(name: String) -> int:
	var index := AudioServer.get_bus_index(name)
	if index == -1 and name != "Master":
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, "Master")
	return index


func _apply_audio() -> void:
	for bus in ["Master", "Music", "SFX", "Ambience"]:
		var level := float(value("audio/" + bus.to_lower()))
		var index := bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(clampf(level, 0.0, 1.0)))
			AudioServer.set_bus_mute(index, level <= 0.001)


func _has_window() -> bool:
	return DisplayServer.get_name() != "headless"


func _apply_window() -> void:
	if not _has_window():
		return
	var win := get_window()
	if win == null:
		return
	if int(value("video/window_mode")) == 1:
		win.mode = Window.MODE_FULLSCREEN
		return
	win.mode = Window.MODE_WINDOWED
	var screen := DisplayServer.window_get_current_screen()
	# Usable rect: the desktop minus taskbars, so the default 1080p window still
	# fits a 1080p panel with its title bar on screen.
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := window_size(int(value("video/window_preset")))
	size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
	win.size = size
	win.position = usable.position + (usable.size - size) / 2


func _apply_ui_scale() -> void:
	var win := get_window()
	if win != null:
		win.content_scale_factor = clampf(float(value("video/ui_scale")), 0.5, 2.5)


func shadow_distance() -> float:
	return SHADOW_DISTANCES[clampi(int(value("video/shadow_quality")), 0, SHADOW_DISTANCES.size() - 1)]


func _apply_shadow_quality() -> void:
	var level := clampi(int(value("video/shadow_quality")), 0, SHADOW_ATLAS.size() - 1)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[level], false)
	if not ClassDB.class_has_method("RenderingServer", "directional_soft_shadow_filter_set_quality"):
		return
	var names := ["SHADOW_QUALITY_HARD", "SHADOW_QUALITY_SOFT_VERY_LOW", "SHADOW_QUALITY_SOFT_MEDIUM"]
	var constant: String = names[level]
	if ClassDB.class_has_integer_constant("RenderingServer", constant):
		RenderingServer.directional_soft_shadow_filter_set_quality(
			ClassDB.class_get_integer_constant("RenderingServer", constant))


## Select a macro preset: it writes the fine-grained video keys through
## set_value, so every value it sets persists, applies, and has its own row.
func _apply_quality_preset(name: String) -> void:
	var preset: Dictionary = QUALITY_PRESETS.get(name, QUALITY_PRESETS["high"])
	for key: String in preset:
		set_value(key, preset[key], false)


func _apply_msaa() -> void:
	var win := get_window()
	if win != null:
		win.msaa_3d = clampi(int(value("video/msaa")), 0, 3)


## Ambient-occlusion cost lever: the renderer keys behind SSAO live in project
## settings, while the visible radius/detail pair lives on the Environment and is
## applied by Game from the same stored value.
func _apply_occlusion_quality() -> void:
	var tier := clampi(int(value("video/ssao")), 0, 2)
	var low := tier == 1
	ProjectSettings.set_setting("rendering/environment/ssao/quality", 1 if low else 2)
	ProjectSettings.set_setting("rendering/environment/ssao/half_size", low)


## The frame cap exists for laptop thermals. Headless runs must never be
## throttled: checks and captures simulate far faster than real time.
func _apply_frame_cap() -> void:
	Engine.max_fps = 0 if not _has_window() else clampi(int(value("video/frame_cap")), 0, 480)


func _sanitize(key: String, value: Variant) -> Variant:
	match key:
		"audio/master", "audio/music", "audio/sfx", "audio/ambience":
			return clampf(_to_number(value, DEFAULTS[key]), 0.0, 1.0)
		"video/window_mode":
			return clampi(int(_to_number(value, 0)), 0, 1)
		"video/window_preset":
			return clampi(int(_to_number(value, DEFAULTS[key])), 0, WINDOW_SIZES.size() - 1)
		"video/quality":
			return str(value).to_lower() if QUALITY_PRESETS.has(str(value).to_lower()) else DEFAULTS[key]
		"video/msaa", "video/ssao":
			return clampi(int(_to_number(value, DEFAULTS[key])), 0, 2)
		"video/glow":
			return bool(value) if typeof(value) == TYPE_BOOL else DEFAULTS[key]
		"video/frame_cap":
			return int(_to_number(value, DEFAULTS[key])) if int(_to_number(value, DEFAULTS[key])) in FRAME_CAPS else DEFAULTS[key]
		"video/ui_scale":
			return clampf(_to_number(value, 1.0), 0.85, 1.5)
		"video/shadows", "camera/invert_y", "camera/recenter", "camera/reduced_motion", "text/subtitles":
			return bool(value) if typeof(value) == TYPE_BOOL else DEFAULTS[key]
		"video/shadow_quality":
			return clampi(int(_to_number(value, DEFAULTS[key])), 0, 2)
		"camera/sensitivity":
			return clampf(_to_number(value, 1.0), 0.25, 3.0)
		"text/speed":
			return clampf(_to_number(value, 1.0), 0.75, 2.0)
	return value


static func _to_number(value: Variant, fallback: float) -> float:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
		return float(value)
	return fallback
