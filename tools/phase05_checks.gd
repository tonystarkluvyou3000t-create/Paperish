extends SceneTree
## Phase 05 menus and settings acceptance:
## title navigation, the Esc back stack, free roam, results copy, live options
## widgets, remapping with conflicts and cancel, layout/accessibility contracts
## and the full new-game -> pause -> options -> restart -> title -> new-game
## route with no stale state.
## godot --headless --audio-driver Dummy --path . --script tools/phase05_checks.gd
const Fixture = preload("res://tools/dev_fixture.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")
const SettingsService = preload("res://scripts/services/settings_service.gd")

const RUN_SETTINGS := "user://phase05-run.cfg"
const TEST_SETTINGS := "user://phase05-persist.cfg"
const CORRUPT_SETTINGS := "user://phase05-corrupt.cfg"

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


## Raw key press+release through the viewport, like phase01's helper. Both
## keycode and physical_keycode are set, as real keyboards report both: the
## builtin ui_* navigation actions match on the logical keycode.
func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press)
	await frame()
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	root.push_input(release)
	await frame()


func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


## Real mouse click at a control's centre, so menus are driven like a player's.
func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	root.push_input(press)
	await frame()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	root.push_input(release)
	await frame()


func snap() -> Dictionary:
	return game.get_snapshot().to_dictionary()


func menu(id: String) -> bool:
	return game.menus.activate(StringName(id))


func screen(id: String) -> Control:
	return game.menus.screen(id)


func find_control(id: String, name: String) -> Control:
	var scr := screen(id)
	if scr == null:
		return null
	return scr.find_child(name, true, false) as Control


func has_prop(obj: Object, name: String) -> bool:
	for entry in obj.get_property_list():
		if str(entry["name"]) == name:
			return true
	return false


func logical_size() -> Vector2:
	return game.get_viewport().get_visible_rect().size


## Horizontal containment: a card must never be wider than the logical view.
func fits_across(rect: Rect2, slack := 2.0) -> bool:
	var logical := logical_size()
	return rect.position.x >= -slack and rect.end.x <= logical.x + slack


## Vertical containment: a card must never grow past the bottom of the view.
func fits_tall(rect: Rect2, slack := 2.0) -> bool:
	var logical := logical_size()
	return rect.position.y >= -slack and rect.end.y <= logical.y + slack


func scroll_reaches(id: String, control_name: String) -> bool:
	var scroll := find_control(id, "Scroll") as ScrollContainer
	var target := find_control(id, control_name)
	if scroll == null or target == null:
		return false
	scroll.scroll_vertical = 100000
	await frame()
	await frame()
	var rect := target.get_global_rect()
	var logical := logical_size()
	return rect.position.y >= -2.0 and rect.end.y <= logical.y + 2.0


func create_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame()
	# Headless boots a 64x64 dummy window; pin the design resolution so menu,
	# click and HUD layout checks exercise the real 1280x720 view.
	game.get_window().size = Vector2i(1280, 720)
	await frame()
	game.set_order_seed(20261018)
	# Keep the suite off the real user://settings.cfg: same code path, own file.
	game.settings.configure(RUN_SETTINGS, true)
	game.settings.load_settings()
	await frame()


func destroy_game() -> void:
	game.settings.reset_to_defaults(false)
	game.queue_free()
	game = null
	await frame()
	await create_timer(0.2).timeout


func ensure_title() -> void:
	if game.session.flow != game.session.Flow.TITLE or snap()["menu_screen"] != "title":
		game.restart()
		await frame()
		await frame()


func run() -> void:
	await create_game()
	if not game.world_ready:
		check(false, "world binds before phase 05 checks")
		finish()
		return
	await title_checks()
	await options_checks()
	await binding_checks()
	await focus_checks()
	await roam_checks()
	await shift_checks()
	await results_checks()
	await route_checks()
	await settings_checks()
	await layout_checks()
	await wiring_checks()
	await destroy_game()
	finish()


func finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CORRUPT_SETTINGS))
	print("PHASE 05: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ title
func title_checks() -> void:
	await ensure_title()
	var s := snap()
	check(s["menu_screen"] == "title", "the boot state shows the title menu")
	check(s["menu_focused"] == "btn_start_shift", "title focus starts on START SHIFT")
	check(s["gameplay_visible"] == false, "the title hides gameplay HUD")
	check(s["play_mode"] == "shift" and s["session_mode"] == "title", "the title is not a run")
	check(not game.hud._cash_card.visible, "cash card hidden under the title")
	check(not game.hud._objective_vb.visible, "objective bar hidden under the title")
	check(not game.hud._prompt_panel.visible, "interaction prompt hidden under the title")
	check(not game.hud._speed_panel.visible, "speed panel hidden under the title")
	check(not game.hud._timer.visible, "shift clock hidden under the title")
	check(not has_prop(game.hud, "_title_blink") and not game.hud.has_method("show_title"),
		"the old blink-only title affordance is gone")
	var start := find_control("title", "btn_start_shift") as Button
	check(start != null and start.pressed.get_connections().size() > 0, "START SHIFT is wired")
	# Keyboard walk: every action is reachable with one DOWN pass.
	var visited := {game.menus.focused_id(): true}
	for i in range(6):
		await key(KEY_DOWN)
		visited[game.menus.focused_id()] = true
	check(visited.size() == 6, "arrow keys reach all six title actions (%d)" % visited.size())
	check(not visited.has(""), "focus never falls to no control")
	await key(KEY_UP)
	check(game.menus.focused_id() != "", "UP navigation also keeps focus on a control")


func options_checks() -> void:
	var opened: bool = menu("options")
	await frame()
	check(opened and snap()["menu_screen"] == "options", "the title opens OPTIONS")
	check(not game.paused, "options over the title never pauses the game")
	var sun := game.get_node("Sun") as DirectionalLight3D
	# Slider: writes through, applies to the bus, updates its own label.
	var slider := find_control("options", "slider_audio_sfx") as HSlider
	check(slider != null, "options builds the sfx slider from the spec")
	slider.value = 0.5
	await frame()
	check(is_equal_approx(float(game.settings.value("audio/sfx")), 0.5), "sfx slider writes to preferences")
	check((find_control("options", "value_audio_sfx") as Label).text == "50%", "slider label shows the percent")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.01,
		"sfx slider moves the real audio bus")
	# Toggle: shadows.
	var toggle := find_control("options", "toggle_video_shadows") as Button
	toggle.pressed.emit()
	await frame()
	check(game.settings.value("video/shadows") == false and sun.shadow_enabled == false,
		"shadows toggle turns the sun shadow off")
	check(toggle.text == "OFF", "shadows toggle reads OFF")
	toggle.pressed.emit()
	await frame()
	check(sun.shadow_enabled == true, "shadows toggle turns the sun shadow back on")
	# Choice: UI scale, applied to the window and still fitting.
	var right := find_control("options", "right_video_ui_scale") as Button
	right.pressed.emit()
	await frame()
	check(is_equal_approx(float(game.settings.value("video/ui_scale")), 1.25), "ui scale stepper writes through")
	check(is_equal_approx(game.get_window().content_scale_factor, 1.25), "ui scale applies to the window")
	var card := find_control("options", "Card")
	check(card != null and fits_across(card.get_global_rect()),
		"options card survives a 125% UI scale")
	var left := find_control("options", "left_video_ui_scale") as Button
	left.pressed.emit()
	await frame()
	check(is_equal_approx(float(game.settings.value("video/ui_scale")), 1.0), "ui scale stepper steps back down")
	# Quality preset: a macro row that writes the fine-grained video keys. Each
	# key keeps its own row, its own apply path and its own stored value.
	var world_env := game.get_node("Environment") as WorldEnvironment
	check((find_control("options", "value_video_quality") as Label).text == "HIGH",
		"the shipped quality preset is HIGH (the 3050 target)")
	var preset_left := find_control("options", "left_video_quality") as Button
	preset_left.pressed.emit()
	await frame()
	check(str(game.settings.value("video/quality")) == "medium", "stepping the preset down writes the macro key")
	check(int(game.settings.value("video/msaa")) == 1 and int(game.settings.value("video/ssao")) == 1,
		"the medium preset writes anti-aliasing and occlusion")
	check(int(game.settings.value("video/shadow_quality")) == 1 and game.settings.value("video/shadows") == true,
		"the medium preset writes the shadow keys")
	check((find_control("options", "value_video_msaa") as Label).text == "2× MSAA",
		"the fine-grained rows show what the preset did")
	check(game.get_window().msaa_3d == 1, "anti-aliasing lands on the live viewport")
	preset_left.pressed.emit()
	await frame()
	check(str(game.settings.value("video/quality")) == "low", "the preset steps down to LOW")
	check(int(game.settings.value("video/msaa")) == 0 and game.get_window().msaa_3d == 0,
		"LOW turns anti-aliasing off on the live viewport")
	check(world_env.environment.ssao_enabled == false and world_env.environment.glow_enabled == false,
		"LOW turns occlusion and glow off in the shipped environment")
	(find_control("options", "right_video_quality") as Button).pressed.emit()
	(find_control("options", "right_video_quality") as Button).pressed.emit()
	await frame()
	check(str(game.settings.value("video/quality")) == "high" and world_env.environment.ssao_enabled == true,
		"stepping back up restores HIGH and its occlusion")
	# Occlusion and glow keep their own rows on top of the preset.
	var occlusion_left := find_control("options", "left_video_ssao") as Button
	occlusion_left.pressed.emit()
	await frame()
	check(int(game.settings.value("video/ssao")) == 1, "the occlusion row steps independently of the preset")
	var low_detail: float = world_env.environment.ssao_detail
	check(world_env.environment.ssao_enabled
		and int(ProjectSettings.get_setting("rendering/environment/ssao/quality", 0)) == 1,
		"a LOW occlusion choice reaches the environment and the renderer keys")
	(find_control("options", "right_video_ssao") as Button).pressed.emit()
	await frame()
	check(world_env.environment.ssao_enabled and world_env.environment.ssao_detail > low_detail,
		"HIGH occlusion is denser than LOW")
	check(int(ProjectSettings.get_setting("rendering/environment/ssao/quality", 0)) == 2
		and ProjectSettings.get_setting("rendering/environment/ssao/half_size", true) == false,
		"HIGH occlusion turns half-size rendering off")
	var glow_toggle := find_control("options", "toggle_video_glow") as Button
	glow_toggle.pressed.emit()
	await frame()
	check(game.settings.value("video/glow") == false and world_env.environment.glow_enabled == false,
		"the glow toggle reaches the shipped environment")
	glow_toggle.pressed.emit()
	await frame()
	check(world_env.environment.glow_enabled == true, "the glow toggle comes back on")
	# Frame cap: stored as a preference, applied to the engine. Headless runs
	# must stay unthrottled so the suite keeps simulating faster than real time.
	(find_control("options", "right_video_frame_cap") as Button).pressed.emit()
	await frame()
	check(int(game.settings.value("video/frame_cap")) == 120, "the frame cap row steps to 120")
	check(Engine.max_fps == 0, "headless runs are never throttled by the frame cap")
	(find_control("options", "right_video_frame_cap") as Button).pressed.emit()
	(find_control("options", "left_video_frame_cap") as Button).pressed.emit()
	(find_control("options", "left_video_frame_cap") as Button).pressed.emit()
	await frame()
	check(int(game.settings.value("video/frame_cap")) == 60, "the frame cap row steps back to 60")
	# Shadow quality still drives the sun's distance.
	var shadow_left := find_control("options", "left_video_shadow_quality") as Button
	shadow_left.pressed.emit()
	await frame()
	check(is_equal_approx(sun.directional_shadow_max_distance, 95.0),
		"shadow quality still drives the sun's shadow distance")
	shadow_left.pressed.emit()
	await frame()
	check(is_equal_approx(sun.directional_shadow_max_distance, 60.0),
		"LOW shadow quality pulls the shadow range in")
	(find_control("options", "right_video_shadow_quality") as Button).pressed.emit()
	(find_control("options", "right_video_shadow_quality") as Button).pressed.emit()
	await frame()
	check(is_equal_approx(sun.directional_shadow_max_distance, 140.0),
		"HIGH shadow quality pushes the shadow range out")
	# The render target is a committed project setting, not an accident.
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus") == "forward_plus",
		"the project targets the Forward+ renderer")
	check(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 0)) == 4096,
		"the shipped shadow atlas is 4096")
	check(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1920
		and int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 1080,
		"the shipped viewport is 1920x1080")
	check(SettingsService.window_size(int(game.settings.value("video/window_preset"))) == Vector2i(1920, 1080),
		"the shipped window preset is 1920x1080")
	# Window rows are explained, not silently dead, without a desktop window.
	var mode_left := find_control("options", "left_video_window_mode") as Button
	if DisplayServer.get_name() == "headless":
		check(mode_left.disabled, "window mode is disabled without a desktop window")
		check((mode_left.get_parent().get_child(0) as Label).text.contains("desktop window only"),
			"the disabled window row explains itself")
	else:
		check(not mode_left.disabled, "window mode is interactive on a desktop window")
	# Reset restores every default and rebuilds the widgets.
	slider = find_control("options", "slider_audio_sfx") as HSlider
	slider.value = 0.2
	await frame()
	(find_control("options", "btn_reset") as Button).pressed.emit()
	await frame()
	await frame()
	check(is_equal_approx(float(game.settings.value("audio/sfx")), 1.0), "RESET restores default volumes")
	check(game.settings.value("video/shadows") == true, "RESET restores default shadows")
	check(is_equal_approx(float(game.settings.value("video/ui_scale")), 1.0), "RESET restores the default UI scale")
	check(str(game.settings.value("video/quality")) == "high", "RESET restores the HIGH quality preset")
	check(int(game.settings.value("video/msaa")) == 2 and game.get_window().msaa_3d == 2,
		"RESET restores 4x MSAA on the live viewport")
	check(is_equal_approx(sun.directional_shadow_max_distance, 140.0),
		"RESET restores the HIGH shadow range")
	slider = find_control("options", "slider_audio_sfx") as HSlider
	check(slider != null and is_equal_approx(slider.value, 1.0), "RESET rebuilds the live widgets")
	await key(KEY_ESCAPE)
	check(snap()["menu_screen"] == "title", "Esc closes options back to the title")
	check(not game.paused, "closing options leaves the game unpaused")


# ------------------------------------------------------------------ bindings
func binding_checks() -> void:
	check(menu("controls"), "the title opens CONTROLS")
	await frame()
	check(snap()["menu_screen"] == "controls", "controls is the top overlay")
	var defaults_prompt := InputBindings.prompt("move_forward")
	var defaults_text: String = game.settings.binding_label("move_forward")
	var chip := find_control("controls", "chip_move_forward") as Button
	check(chip != null, "controls lists MOVE FORWARD")
	check(chip.text == defaults_text, "the chip shows the current binding")
	# Capture a fresh key.
	chip.pressed.emit()
	await frame()
	check(chip.text.begins_with("PRESS"), "clicking a chip waits for input")
	await key(KEY_K)
	check(InputBindings.prompt("move_forward") == "K", "the captured key lands in InputMap")
	check(chip.text == "K", "the chip shows the new key")
	check(game.settings.binding_label("move_forward") == "K", "the service reports the new binding")
	# Conflict: K already belongs to MOVE FORWARD.
	var chip_left := find_control("controls", "chip_move_left") as Button
	chip_left.pressed.emit()
	await frame()
	await key(KEY_K)
	check(InputBindings.prompt("move_left") == "A", "a conflicting key is refused")
	check((game.menus.screen("controls")._status as Label).text.contains("MOVE FORWARD"),
		"the conflict message names the other action")
	check((game.menus.screen("controls")._capturing as String) == "move_left",
		"the refused capture keeps listening")
	check(chip_left.text == game.settings.binding_label("move_left"), "the refused chip keeps the old key")
	# Esc cancels the capture instead of leaving the screen.
	await key(KEY_ESCAPE)
	check((game.menus.screen("controls")._capturing as String) == "", "Esc cancels an active capture")
	check(snap()["menu_screen"] == "controls", "Esc during a capture does not leave the screen")
	check(InputBindings.prompt("move_left") == "A", "cancelling keeps the old binding")
	check(chip_left.text == game.settings.binding_label("move_left"), "the cancelled chip shows the kept binding")
	# Movement can never be unbound.
	check(game.settings.set_binding("move_forward", null) == "invalid", "clearing a critical action is refused")
	check(InputBindings.prompt("move_forward") == "K", "the refused clear keeps the action bound")
	# Reset controls.
	(find_control("controls", "btn_reset_controls") as Button).pressed.emit()
	await frame()
	check(InputBindings.prompt("move_forward") == defaults_prompt, "RESET CONTROLS restores defaults")
	check(chip.text == defaults_text, "the chip refreshes after a controls reset")
	check((game.menus.screen("controls")._status as Label).text.contains("defaults"),
		"the status line confirms the reset")
	await key(KEY_ESCAPE)
	check(snap()["menu_screen"] == "title", "Esc leaves controls back to the title")
	# Interact prompt follows the binding.
	var interact_prompt: String = game.presentation.interact_label()
	game.settings.set_binding("interact", key_event(KEY_J))
	check(game.presentation.interact_label() == "J", "the HUD prompt follows a remapped interact key")
	game.start_shift()
	await frame()
	Fixture.place(game, "pip", game.van.global_position + game.van.global_basis.x * 1.5)
	await frames(3)
	game.presentation.update_context()
	check(game.presentation.prompt_text.begins_with("[J]"), "the van prompt shows the remapped key")
	game.settings.set_binding("interact", key_event(KEY_E))
	game.restart()
	await frame()
	check(game.presentation.interact_label() == interact_prompt, "restoring interact restores the prompt")
	# The rebindable confirm action reaches the focused menu action.
	check(game.settings.set_binding("confirm", key_event(KEY_Z)) == "", "confirm can be rebound")
	await ensure_title()
	(find_control("title", "btn_start_shift") as Button).grab_focus()
	await frame()
	await key(KEY_Z)
	await frame()
	check(snap()["session_mode"] == "playing", "the rebound confirm key starts the focused action")
	game.restart()
	await frame()
	game.settings.set_binding("confirm", key_event(KEY_ENTER))
	check(game.settings.binding_label("confirm") == "ENTER", "confirm returns to Enter")


func focus_checks() -> void:
	await ensure_title()
	var credits := find_control("title", "btn_credits") as Button
	credits.grab_focus()
	await frame()
	check(game.menus.focused_id() == "btn_credits", "focus can land on CREDITS")
	check(menu("credits"), "the title opens CREDITS")
	await frame()
	check(snap()["menu_screen"] == "credits", "credits is the top overlay")
	await key(KEY_ESCAPE)
	await frame()
	check(snap()["menu_screen"] == "title", "Esc closes credits")
	check(game.menus.focused_id() == "btn_credits", "closing credits restores the previous focus")
	# A real mouse click drives the same path as the keyboard.
	var roam_button := find_control("title", "btn_start_roam") as Button
	await click(roam_button)
	check(snap()["menu_screen"] == "" and snap()["session_mode"] == "playing",
		"clicking FREE ROAM starts a run")
	game.restart()
	await frame()
	check(snap()["menu_screen"] == "title", "restart returns to the title")


# ------------------------------------------------------------------ free roam
func roam_checks() -> void:
	check(menu("start_roam"), "the title starts FREE ROAM")
	await frame()
	var s := snap()
	check(s["play_mode"] == "roam" and s["session_mode"] == "playing", "roam runs in the world as a playing session")
	check(game.free_roam(), "the roam flag is on")
	check(s["gameplay_visible"] == true and s["menu_screen"] == "", "roam shows the world with no overlay")
	check(s["timer_visible"] == false and not game.hud._timer.visible, "roam has no shift clock")
	check(not game.hud._cash_card.visible, "roam hides the shift cash card")
	check(game.hud._hint.visible and game.hud._hint.text.contains("FREE ROAM"),
		"the HUD names free roam and its missing clock")
	check(not game.hud._objective.visible, "roam shows no objective text")
	check(s["order_lifecycle"] == "idle" and game.orders.order_id == 0, "roam creates no ticket")
	# The town stays playable: walk, drive, and nothing settles.
	Fixture.place(game, "pip", game.pickup_point.global_position + Vector3(0, 0, 1.0))
	await frames(4)
	game.interact()
	await frames(4)
	check(game.pip.carrying == 0 and snap()["order_lifecycle"] == "idle",
		"the shop counter is dormant in free roam")
	check(await click_near_van_and_drive(), "roam lets the player drive")
	var roam_timer: float = snap()["timer"]
	await frames(30)
	check(snap()["timer"] == roam_timer and snap()["order_lifecycle"] == "idle",
		"roam never starts a failure clock")
	check(game.hud._speed_panel.visible, "the speed panel works while roaming")
	await key(KEY_ESCAPE)
	check(game.paused and snap()["menu_screen"] == "pause", "roam pauses like a shift")
	await key(KEY_ESCAPE)
	check(not game.paused and game.driving, "roam resumes with the player still driving")
	check(game.free_roam(), "the roam flag survives the pause round trip")
	await key(KEY_ESCAPE)
	await frame()
	check(menu("restart_shift") and menu("confirm_yes"), "roam can be restarted from the pause menu")
	await frame()
	check(not game.driving and not game.paused, "the roam restart clears the seat and the pause")
	check(game.free_roam() and snap()["play_mode"] == "roam", "restarting free roam keeps the clock-free mode")
	check(snap()["menu_screen"] == "" and snap()["order_lifecycle"] == "idle", "the roam restart has no ticket")
	game.restart()
	await frame()
	check(not game.free_roam() and snap()["menu_screen"] == "title", "restarting leaves free roam cleanly")
	check(not game.driving and not game.paused, "a fresh title has no roaming leftovers")


func click_near_van_and_drive() -> bool:
	Fixture.place(game, "pip", game.van.global_position + game.van.global_basis.x * 1.5)
	await frames(4)
	game.interact()
	await frames(4)
	return game.driving


# ------------------------------------------------------------------ shift, pause, confirm
func shift_checks() -> void:
	await ensure_title()
	check(menu("start_shift"), "the title starts a SHIFT")
	await frame()
	var s := snap()
	check(s["session_mode"] == "playing" and s["gameplay_visible"], "a shift starts playing")
	check(s["menu_screen"] == "", "no overlay during play")
	check(game.hud._cash_card.visible and game.hud._ticket_card.visible and game.hud._objective_vb.visible,
		"the shift HUD shows money, ticket and objective during preparation")
	check(s["play_mode"] == "shift" and not s["timer_visible"] and s["ticket_state"] == "preparing",
		"the delivery clock waits for receipt")
	await key(KEY_ESCAPE)
	check(game.paused and snap()["menu_screen"] == "pause", "Esc opens the pause menu")
	check(snap()["menu_focused"] == "btn_resume", "the pause menu focuses RESUME")
	for id in ["btn_resume", "btn_options", "btn_controls", "btn_restart_shift", "btn_return_to_title", "btn_quit"]:
		check(find_control("pause", id) != null, "the pause menu offers " + id)
	# Sub-screens open above the pause menu without resuming it.
	check(menu("options"), "the pause menu opens OPTIONS")
	await frame()
	check(snap()["menu_screen"] == "options" and game.paused, "options sits above the paused game")
	await key(KEY_ESCAPE)
	await frame()
	check(snap()["menu_screen"] == "pause" and game.paused,
		"Esc closes one screen only and never resumes in the same event")
	check(menu("controls"), "the pause menu opens CONTROLS")
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(snap()["menu_screen"] == "pause" and game.paused, "Esc closes controls back to pause")
	# Esc on pause resumes.
	await key(KEY_ESCAPE)
	check(not game.paused and snap()["menu_screen"] == "", "Esc on pause resumes the shift")
	check(not game.hud._timer.visible, "resuming keeps the delivery clock hidden during preparation")
	# Destructive actions ask first.
	await key(KEY_ESCAPE)
	var generation: int = snap()["generation"]
	check(menu("restart_shift"), "RESTART SHIFT opens a confirm")
	await frame()
	check(snap()["menu_screen"] == "confirm", "destructive actions ask first")
	check(snap()["menu_focused"] == "btn_confirm_no", "the confirm defaults to the safe choice")
	check(menu("confirm_no"), "the confirm can be dismissed")
	await frame()
	check(snap()["menu_screen"] == "pause" and game.paused and snap()["generation"] == generation,
		"dismissing the confirm leaves the run untouched")
	check(menu("restart_shift") and menu("confirm_yes"), "the confirm can be accepted")
	await frame()
	check(not game.paused and snap()["generation"] > generation and snap()["session_mode"] == "playing",
		"the confirmed restart runs a fresh shift")
	check(snap()["money"] == 0 and snap()["deliveries"] == 0 and not game.driving,
		"the fresh shift has no stale money, deliveries or seat")
	# Quit asks for confirmation too, and we never accept it.
	await key(KEY_ESCAPE)
	check(menu("quit"), "QUIT asks before closing")
	await frame()
	check(snap()["menu_screen"] == "confirm", "quitting is confirmed first")
	check(menu("confirm_no"), "the quit confirm can be dismissed")
	await frame()
	check(snap()["menu_screen"] == "pause" and game.paused, "the dismissed quit keeps the run running")


# ------------------------------------------------------------------ results
func results_checks() -> void:
	check(menu("resume"), "the pause menu resumes")
	await frame()
	game.orders.money = 37
	game.orders.deliveries = 3
	game.orders.total_base = 30
	game.orders.total_pizza = 6
	game.orders.total_tip = 1
	game.hud.toast("NEW ORDER · a toast is still fading")
	await frame()
	check(game.hud._toast_t > 0.0, "fixture: a toast is on screen before the shift ends")
	Fixture.finish(game, true)
	await frame()
	var s := snap()
	check(s["session_mode"] == "result" and s["menu_screen"] == "results", "finishing shows the results screen")
	check(s["gameplay_visible"] == false, "results hide the gameplay HUD")
	check(not game.hud._cash_card.visible and not game.hud._objective_vb.visible,
		"results hide money and objective furniture")
	check(game.hud._toast_t == 0.0 and is_zero_approx(game.hud._toast.modulate.a),
		"a fading gameplay toast does not float over the results")
	var title := find_control("results", "Title") as Label
	var body := find_control("results", "Body") as Label
	check(title != null and title.text == "SHIFT COMPLETE", "a won shift says SHIFT COMPLETE")
	check(body != null and body.text.contains("DELIVERIES  3"), "the results body counts deliveries")
	check(body.text.contains("$37"), "the results body states the earnings")
	check(body.text.contains("base $30") and body.text.contains("pizza $6") and body.text.contains("tips $1"),
		"the results body itemizes base, pizza and tips")
	check(body.text.contains("STRIKES  0 / %d" % game.max_strikes), "the results body shows strikes against the limit")
	# Retry resets everything.
	check(menu("restart_shift"), "results offer RETRY")
	await frame()
	s = snap()
	check(s["session_mode"] == "playing" and s["money"] == 0 and s["deliveries"] == 0 and not game.paused,
		"retrying starts a clean shift")
	# A failed shift reports honestly and Esc returns to the title.
	Fixture.finish(game, false)
	await frame()
	title = find_control("results", "Title") as Label
	body = find_control("results", "Body") as Label
	check(title.text == "SHIFT OVER", "a lost shift says SHIFT OVER")
	check(body.text.contains("COLD"), "the loss reason names the cold orders")
	await key(KEY_ESCAPE)
	await frame()
	check(snap()["menu_screen"] == "title" and snap()["session_mode"] == "title",
		"Esc on results returns to the title")
	check(not game.paused and not game.driving, "returning to the title clears pause and driving")


# ------------------------------------------------------------------ route
func route_checks() -> void:
	await ensure_title()
	var generation: int = snap()["generation"]
	check(menu("start_shift"), "route: new game from the title")
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(game.paused, "route: paused")
	check(menu("options"), "route: options opened from pause")
	await frame()
	game.settings.set_value("text/speed", 1.5, false)
	check(is_equal_approx(game.hud.text_speed, 1.5), "route: an options change applies live")
	await key(KEY_ESCAPE)
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(not game.paused and snap()["menu_screen"] == "", "route: resumed")
	await key(KEY_ESCAPE)
	await frame()
	check(menu("restart_shift") and menu("confirm_yes"), "route: restart from pause")
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(menu("return_to_title") and menu("confirm_yes"), "route: back to the title")
	await frame()
	check(snap()["menu_screen"] == "title" and snap()["session_mode"] == "title", "route: title reached")
	check(not game.paused and not game.driving, "route: no pause or seat left behind")
	check(not game.pip.input_enabled, "route: walking is disabled on the title")
	check(snap()["camera_mode"] == "title", "route: the camera returns to its title orbit")
	check(snap()["money"] == 0 and snap()["deliveries"] == 0, "route: the run ledger is empty again")
	check(menu("start_shift"), "route: new game again")
	await frame()
	var s := snap()
	check(not game.paused and s["session_mode"] == "playing", "route: the new run plays")
	check(s["generation"] > generation, "route: the new run has a fresh generation")
	check(s["money"] == 0 and s["strikes"] == 0 and s["cargo_count"] == 0, "route: the new run starts empty")
	check(s["order_lifecycle"] == "at_shop" and s["order_pizzas"] > 0, "route: the new run has its first ticket")
	check(s["ticket_state"] == "preparing" and float(s["preparation_remaining"]) > 0.0
		and is_zero_approx(float(s["timer"])), "route: the new run starts with prep and no delivery clock")
	check(s["driving"] == false and game.pip.input_enabled, "route: control is back with the player")
	check(s["camera_mode"] == "foot", "route: the camera follows on foot")
	await key(KEY_ESCAPE)
	await frame()
	check(game.paused and snap()["menu_screen"] == "pause", "route: paused for the R shortcut")
	await key(KEY_R)
	await frame()
	check(snap()["menu_screen"] == "title", "the R shortcut still resets instantly while paused")
	game.settings.set_value("text/speed", 1.0, false)


# ------------------------------------------------------------------ settings service
func settings_checks() -> void:
	var first := SettingsService.new()
	root.add_child(first)
	first.configure(TEST_SETTINGS, true)
	first.load_settings()
	check(is_equal_approx(float(first.value("audio/master")), 1.0), "a missing settings file falls back to defaults")
	check(first.value("camera/recenter") == true and first.value("video/shadows") == true,
		"boolean defaults load as shipped")
	var expected_ui := float(first.value("video/ui_scale"))
	check(expected_ui >= 0.85 and expected_ui <= 1.5, "ui scale default is inside the allowed band")
	first.set_value("audio/sfx", 0.35)
	first.set_value("camera/sensitivity", 9.0)
	check(is_equal_approx(float(first.value("camera/sensitivity")), 3.0), "sensitivity is clamped on the way in")
	first.set_value("camera/sensitivity", 0.1)
	check(is_equal_approx(float(first.value("camera/sensitivity")), 0.25), "sensitivity clamps at the low end too")
	first.set_value("video/window_mode", 7)
	check(int(first.value("video/window_mode")) == 1, "window mode clamps to the valid range")
	first.set_value("video/ui_scale", 9.0)
	check(is_equal_approx(float(first.value("video/ui_scale")), 1.5), "ui scale clamps at 150%")
	first.set_value("video/ui_scale", expected_ui)
	first.set_value("text/speed", 99.0)
	check(is_equal_approx(float(first.value("text/speed")), 2.0), "text speed clamps at 200%")
	first.set_value("text/speed", 1.0)
	check(first.is_default("text/speed"), "returning a value to its default reports as default")
	check(first.set_binding("handbrake", key_event(KEY_B)) == "", "a free key binds cleanly")
	check(first.save(), "settings save to disk")
	var second := SettingsService.new()
	root.add_child(second)
	second.configure(TEST_SETTINGS, false)
	second.load_settings()
	check(is_equal_approx(float(second.value("audio/sfx")), 0.35), "a saved volume loads in a fresh instance")
	check(is_equal_approx(float(second.value("camera/sensitivity")), 0.25), "a clamped value stays clamped after a reload")
	check(InputBindings.prompt("handbrake") == "B", "a saved remap loads in a fresh instance")
	check(second.binding_label("handbrake") == "B", "the reloaded binding is reported to the UI")
	second.reset_to_defaults(false)
	check(InputBindings.prompt("handbrake") == "SPACE", "resetting restores the shipped handbrake")
	check(is_equal_approx(float(second.value("audio/sfx")), 1.0), "resetting restores the shipped volume")
	check(InputBindings.prompt("move_forward") == "W", "resetting keeps movement on the shipped keys")
	# A file full of wrong types and out-of-range values must not break startup:
	# every stored value is validated key by key.
	var file := FileAccess.open(CORRUPT_SETTINGS, FileAccess.WRITE)
	file.store_string("[meta]\nversion = 1\n[audio]\nmaster = \"loud\"\nsfx = 0.42\n[video]\nui_scale = 97\nshadows = \"yes\"\nquality = \"ULTRA!\"\nmsaa = -3\nframe_cap = \"fast\"\n[camera]\nsensitivity = -4\n[text]\nspeed = 99\n")
	file.close()
	var third := SettingsService.new()
	root.add_child(third)
	third.configure(CORRUPT_SETTINGS, false)
	third.load_settings()
	check(is_equal_approx(float(third.value("audio/master")), 1.0),
		"a non-numeric volume falls back to its default")
	check(is_equal_approx(float(third.value("audio/sfx")), 0.42), "a valid stored value survives")
	check(is_equal_approx(float(third.value("video/ui_scale")), 1.5), "an out-of-range choice is clamped on load")
	check(third.value("video/shadows") == true, "a wrong-typed toggle falls back to its default")
	check(str(third.value("video/quality")) == "high", "an unknown preset name falls back to HIGH")
	check(int(third.value("video/msaa")) == 0, "an out-of-range anti-aliasing value clamps to OFF")
	check(int(third.value("video/frame_cap")) == 60, "a nonsense frame cap falls back to 60")
	check(is_equal_approx(float(third.value("camera/sensitivity")), 0.25), "a negative sensitivity clamps to the floor")
	check(is_equal_approx(float(third.value("text/speed")), 2.0), "an oversized text speed clamps to the ceiling")
	third.queue_free()
	second.queue_free()
	first.queue_free()
	await frame()


# ------------------------------------------------------------------ layout and HUD contracts
func layout_checks() -> void:
	await ensure_title()
	check(menu("start_shift"), "layout: a shift starts for HUD checks")
	await frame()
	check(game.hud._hint_card.visible, "the address card shows during a shift")
	# Long address, long objective: nothing may collide or leave the view.
	game.presentation.target_label = "14 LONG PROMENADE OF EXTRA CHEESE AND HOT OLIVES"
	game.presentation.target_sub = "TIP  $8  ·  RING TWICE"
	game.presentation.objective_text = "DELIVER TO 14 LONG PROMENADE OF EXTRA CHEESE AND HOT OLIVES"
	await frames(3)
	check(not game.hud._hint_card.get_global_rect().intersects(game.hud._cash_card.get_global_rect()),
		"a long address never overlaps the cash card")
	check(fits_across(game.hud._hint_card.get_global_rect()), "the address card stays inside the view")
	check(fits_across(game.hud._cash_card.get_global_rect()) and fits_across(game.hud._objective_vb.get_global_rect()),
		"money and objective stay inside the view with long text")
	# Enlarged UI scale: HUD and every menu card stay usable.
	game.settings.set_value("video/ui_scale", 1.5, false)
	await frames(3)
	check(fits_across(game.hud._hint_card.get_global_rect()), "the address card fits at a 150% UI scale")
	check(fits_across(game.hud._cash_card.get_global_rect()), "the cash card fits at a 150% UI scale")
	check(fits_across(game.hud._timer.get_global_rect()), "the clock fits at a 150% UI scale")
	await key(KEY_ESCAPE)
	await frame()
	var pause_card := find_control("pause", "Card")
	check(pause_card != null and fits_across(pause_card.get_global_rect()),
		"the pause card fits at a 150% UI scale")
	check(await scroll_reaches("pause", "btn_quit"), "every pause action stays reachable at a 150% UI scale")
	check(menu("options"), "layout: options open at a 150% UI scale")
	await frame()
	var options_card := find_control("options", "Card")
	check(options_card != null and fits_across(options_card.get_global_rect()),
		"the options card fits at a 150% UI scale")
	check(options_card != null and fits_tall(options_card.get_global_rect()),
		"the options card stays inside the view vertically at a 150% UI scale")
	check(await scroll_reaches("options", "btn_back"), "the options footer stays reachable at a 150% UI scale")
	await key(KEY_ESCAPE)
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(not game.paused, "layout: resumed at the normal scale path")
	game.settings.set_value("video/ui_scale", 1.0, false)
	await frames(2)
	check(is_equal_approx(game.get_window().content_scale_factor, 1.0), "ui scale returns to 100%")
	# 1920x1080 is the shipping window: the options list must use the room it
	# gains there instead of keeping the 720p scroll window forever.
	game.get_window().size = Vector2i(1920, 1080)
	await frames(2)
	check(menu("options"), "layout: options open at the shipping resolution")
	await frame()
	var tall_scroll := find_control("options", "Rows") as ScrollContainer
	check(tall_scroll != null and tall_scroll.custom_minimum_size.y >= 560.0,
		"a 1080p window gives the options list the room (got %s of %s)" % [
			"null" if tall_scroll == null else str(tall_scroll.custom_minimum_size.y),
			str(logical_size())])
	check(find_control("options", "Card") != null
		and fits_tall((find_control("options", "Card") as Control).get_global_rect()),
		"the options card still fits vertically at 1080p")
	check(await scroll_reaches("options", "btn_back"), "the options footer stays reachable at 1080p")
	await key(KEY_ESCAPE)
	await frame()
	game.get_window().size = Vector2i(1280, 720)
	await frames(2)
	# Reduced motion: the title orbit stops moving.
	game.restart()
	await frame()
	game.settings.set_value("camera/reduced_motion", true, false)
	await frames(6)
	var yaw: float = game.camera.yaw
	await frames(20)
	check(absf(angle_difference(yaw, game.camera.yaw)) < 0.02,
		"reduced motion holds the title camera still")
	game.settings.set_value("camera/reduced_motion", false, false)
	await frames(20)
	check(absf(angle_difference(yaw, game.camera.yaw)) > 0.02,
		"the title camera drifts again once reduced motion is off")


# ------------------------------------------------------------------ wiring
func wiring_checks() -> void:
	await ensure_title()
	# Build the remaining screens so the scan covers them.
	check(menu("credits"), "wiring: credits open")
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(game.start_shift(), "wiring: a shift starts")
	await frame()
	await key(KEY_ESCAPE)
	await frame()
	check(menu("resume"), "wiring: paused and resumed on the way to the results")
	await frame()
	Fixture.finish(game, false)
	await frame()
	check(snap()["menu_screen"] == "results", "wiring: results screen is built")
	await key(KEY_ESCAPE)
	await frame()
	var allowed_disabled := {
		"options": ["left_video_window_mode", "right_video_window_mode",
			"left_video_window_preset", "right_video_window_preset"],
	}
	var unwired: Array[String] = []
	for id in game.menus._pool.keys():
		var scr := screen(str(id))
		var allowed: Array = allowed_disabled.get(str(id), [])
		for node in scr.find_children("*", "Button", true, false):
			var button := node as Button
			if button.disabled and str(button.name) in allowed:
				continue
			if button.pressed.get_connections().is_empty():
				unwired.append("%s/%s" % [id, button.name])
	check(unwired.is_empty(), "every menu button is wired (dead: %s)" % ", ".join(unwired))
	# Titles, labels and copy exist where the acceptance expects them.
	check((find_control("credits", "btn_back") as Button).text == "BACK", "credits offer a way back")
	check(find_control("title", "Board") != null, "the title builds its board")
	check(find_control("results", "Title") != null and find_control("results", "Body") != null,
		"results expose title and body labels")
	# Settings survive a save/load cycle on the game's own path.
	game.settings.set_value("video/ui_scale", 1.25)
	game.settings.set_value("video/ui_scale", 1.0, false)
	game.settings.load_settings()
	check(is_equal_approx(float(game.settings.value("video/ui_scale")), 1.25),
		"the game's own settings path round-trips a saved value")
	game.settings.set_value("video/ui_scale", 1.0)
	game.settings.load_settings()
	check(is_equal_approx(game.get_window().content_scale_factor, 1.0),
		"reloading the game settings restores the live UI scale")
