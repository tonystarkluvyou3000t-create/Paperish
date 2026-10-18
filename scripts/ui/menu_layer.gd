extends CanvasLayer
## Menu navigation owner. Screens are pooled full-rect Controls stacked in
## order; only the top screen is visible and owns focus. The layer reads
## SessionService flow/pause and emits `menu_action` for the Game to execute,
## so no menu writes session, order or actor state directly.
##
## Every screen scrolls when its card is taller than the viewport, so enlarged
## UI scale settings can never hide an action.

signal menu_action(id: StringName)

const UIF = preload("res://scripts/ui/ui_factory.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")
const OptionsScreen = preload("res://scripts/ui/options_screen.gd")
const ControlsScreen = preload("res://scripts/ui/controls_screen.gd")

const USER_PAUSE := &"user_pause"

var game: Node
var settings: Node
var _pool: Dictionary = {}
var _stack: Array[String] = []
var _pending: StringName = &""
var _title_help: Label


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(game_node: Node, settings_node: Node) -> void:
	game = game_node
	settings = settings_node
	if settings:
		settings.input_changed.connect(_refresh_title_help)
	if not game.session.changed.is_connected(_on_session_changed):
		game.session.changed.connect(_on_session_changed)


func is_open() -> bool:
	return not _stack.is_empty()


func top_id() -> String:
	return _stack[-1] if not _stack.is_empty() else ""


func focused_id() -> String:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner == null:
		return ""
	return owner.name if not owner.name.is_empty() else owner.get_class()


## Top screen instance, for checks and for callers that need its widgets.
func screen(id: String) -> Control:
	return _pool.get(id, null)


## The rebindable `confirm` action is a real second route into the menus: with the
## shipped bindings it is Enter, which the builtin ui_accept already turns into a
## press on the focused button, so this only acts once a rebind separates the two.
func _input(event: InputEvent) -> void:
	if _stack.is_empty() or not event.is_action_pressed("confirm"):
		return
	if event.is_action_pressed("ui_accept"):
		return
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner is BaseButton and _top() != null and (_top() as Control).is_ancestor_of(owner):
		get_viewport().set_input_as_handled()
		(owner as BaseButton).pressed.emit()


# ------------------------------------------------------------------ navigation
## Single entry point for every menu button and for tests. Internal ids open
## screens or close the top one; game ids are emitted for the Game to execute.
func activate(id: StringName) -> bool:
	make_cursor_visible()
	match id:
		&"options":
			_push("options")
		&"controls":
			_push("controls")
		&"credits":
			_push("credits")
		&"back":
			return handle_back()
		&"confirm_yes":
			if top_id() == "confirm":
				var pending := _pending
				_pending = &""
				pop()
				if not pending.is_empty():
					menu_action.emit(pending)
		&"confirm_no":
			if top_id() == "confirm":
				_pending = &""
				pop()
		&"restart_shift", &"return_to_title", &"quit":
			if top_id() == "pause":
				_open_confirm(id)
			else:
				menu_action.emit(id)
		&"start_shift", &"start_roam", &"resume":
			menu_action.emit(id)
		_:
			return false
	return true


## Esc/back. Returns true when the layer consumed the event. Capture states and
## the confirm dialog handle themselves first, so Esc never both closes a
## subpanel and resumes the game.
func handle_back() -> bool:
	var top := _top()
	if top == null:
		return false
	if top.has_method("handle_back") and top.call("handle_back"):
		return true
	match top_id():
		"title":
			return false
		"pause":
			activate(&"resume")
		"results":
			activate(&"return_to_title")
		"confirm":
			activate(&"confirm_no")
		_:
			return pop()
	return true


## Fatal-error presentation: a message card with a quit route.
func show_message(title: String, body: String) -> void:
	_show_only("message")
	var text := _card_text("message")
	if text == null:
		return
	(text.get_node("Title") as Label).text = title
	(text.get_node("Body") as Label).text = body


# ------------------------------------------------------------------ flow
func _on_session_changed(_event: Dictionary) -> void:
	match game.session.flow:
		game.session.Flow.TITLE:
			_show_only("title")
		game.session.Flow.RESULT:
			_show_only("results")
		_:
			if game.session.paused and USER_PAUSE in game.session.reasons():
				_push("pause")
			elif not game.session.paused:
				_stack.clear()
				_refresh()


func _show_only(id: String) -> void:
	_stack = [id]
	var screen := _screen(id)
	_refresh()
	if screen != null:
		if id == "results":
			_refresh_results()
		_focus(screen)
		make_cursor_visible()


func _push(id: String) -> void:
	if top_id() == id:
		return
	var top := _top()
	if top != null:
		_capture_focus(top)
	_stack.append(id)
	var screen := _screen(id)
	_refresh()
	if screen != null:
		_focus(screen)
		make_cursor_visible()


func pop() -> bool:
	if _stack.size() <= 1:
		return false
	_capture_focus(_top())
	_stack.pop_back()
	_refresh()
	var top := _top()
	if top != null:
		_focus(top)
	return true


func _open_confirm(pending: StringName) -> void:
	_pending = pending
	_push("confirm")
	var text := _card_text("confirm")
	if text == null:
		return
	var reason := "RESTART THE RUN?" if pending == &"restart_shift" else (
		"RETURN TO TITLE?" if pending == &"return_to_title" else "QUIT THE GAME?")
	var body := "Any progress in the current run is discarded." if pending == &"quit" else (
		"Current deliveries, money and strikes are discarded.")
	(text.get_node("Title") as Label).text = reason
	(text.get_node("Body") as Label).text = body


func _refresh() -> void:
	for id in _pool:
		_pool[id].visible = not _stack.is_empty() and id == _stack[-1]
	# Screens that keep live widgets rebuild them when they come to the top: a
	# window resize or a quality preset changes what they must show. Runs before
	# `_focus`, so rebuilt rows are focusable on arrival.
	var top := _top()
	if top != null and top.has_method("refresh_values"):
		top.call("refresh_values")


func _top() -> Control:
	return _pool.get(_stack[-1], null) if not _stack.is_empty() else null


## Focus the screen's remembered control, else its first action. Deferred so a
## freshly shown Control is focusable in the same frame.
func _focus(screen: Control) -> void:
	var target: Control = null
	if screen.has_meta("last_focus"):
		var stored = screen.get_meta("last_focus")
		if stored is Control and is_instance_valid(stored) and (stored as Control).is_visible_in_tree():
			target = stored
	if target == null and screen.has_meta("initial_focus"):
		var initial = screen.get_meta("initial_focus")
		if initial is Control and is_instance_valid(initial):
			target = initial
	if target != null:
		target.call_deferred("grab_focus")


func _capture_focus(screen: Control) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and screen.is_ancestor_of(owner):
		screen.set_meta("last_focus", owner)


func make_cursor_visible() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ screens
func _screen(id: String) -> Control:
	if _pool.has(id):
		return _pool[id]
	var screen: Control
	match id:
		"title": screen = _build_title()
		"pause": screen = _build_pause()
		"results": screen = _build_results()
		"credits": screen = _build_credits()
		"confirm": screen = _build_confirm()
		"message": screen = _build_message()
		"options":
			var options := OptionsScreen.new()
			options.setup(settings, func() -> void: activate(&"back"))
			screen = options
		"controls":
			var controls := ControlsScreen.new()
			controls.setup(settings, func() -> void: activate(&"back"))
			screen = controls
	if screen == null:
		return null
	screen.name = "Screen_" + id
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)
	screen.visible = false
	_pool[id] = screen
	return screen


func _card_text(id: String) -> VBoxContainer:
	var screen: Control = _pool.get(id, null)
	if screen == null:
		return null
	return screen.find_child("Text", true, false) as VBoxContainer


func _button(id: StringName, text: String, width := 300.0, height := 44.0) -> Button:
	var b := UIF.button(text, width, 19)
	b.custom_minimum_size = Vector2(width, height)
	b.name = "btn_" + str(id)
	b.pressed.connect(activate.bind(id))
	return b


## Center `content` on screen inside a full-rect scroll area: fits at any UI
## scale, scrolls (with focus following) when the card is taller than the view.
func _centered_card(screen: Control, content: Control, content_name := "Card") -> void:
	UIF.centered(screen, content, content_name)


func _build_title() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.55))
	var vb := UIF.column(6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIF.label("PIP THE PIZZA BOY", 48, UIF.IVORY, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UIF.label("hot pizza, small island, sharp clock", 18, UIF.GOLD)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(UIF.spacer(10))
	var start := _button(&"start_shift", "START SHIFT")
	var roam := _button(&"start_roam", "FREE ROAM  ·  NO CLOCK")
	var options := _button(&"options", "OPTIONS")
	var controls := _button(&"controls", "CONTROLS")
	var credits := _button(&"credits", "CREDITS")
	var quit := _button(&"quit", "QUIT")
	for b: Button in [start, roam, options, controls, credits, quit]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(b)
	vb.add_child(UIF.spacer(10))
	_title_help = UIF.label("", 15, UIF.CREAM)
	_title_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title_help)
	_refresh_title_help()
	_centered_card(screen, vb, "Board")
	screen.set_meta("initial_focus", start)
	return screen


func _refresh_title_help() -> void:
	if _title_help == null or settings == null:
		return
	_title_help.text = "MOVE  %s %s %s %s     ·     INTERACT  %s     ·     HANDBRAKE  %s\nCAMERA  drag / wheel  ·  %s recenter  ·  %s free     ·     MENUS  arrows or stick  ·  enter selects  ·  esc back" % [
		InputBindings.prompt("move_forward"), InputBindings.prompt("move_left"),
		InputBindings.prompt("move_back"), InputBindings.prompt("move_right"),
		InputBindings.prompt("interact"), InputBindings.prompt("handbrake"),
		InputBindings.prompt("cam_recenter"), InputBindings.prompt("cam_free")]


func _build_pause() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.6))
	var card := UIF.dark_panel(20)
	var vb := UIF.column(6)
	card.add_child(vb)
	var title := UIF.label("PAUSED", 34, UIF.IVORY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(UIF.spacer(6))
	var resume := _button(&"resume", "RESUME")
	var options := _button(&"options", "OPTIONS")
	var controls := _button(&"controls", "CONTROLS")
	var restart := _button(&"restart_shift", "RESTART RUN …")
	var title_btn := _button(&"return_to_title", "RETURN TO TITLE …")
	var quit := _button(&"quit", "QUIT …")
	for b: Button in [resume, options, controls, restart, title_btn, quit]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(b)
	var hint := UIF.label("the world waits while paused  ·  esc resumes", 15, UIF.CREAM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	_centered_card(screen, card)
	screen.set_meta("initial_focus", resume)
	return screen


func _build_results() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.62))
	var card := UIF.dark_panel(22)
	var vb := UIF.column(8)
	vb.name = "Text"
	card.add_child(vb)
	var title := UIF.label("SHIFT COMPLETE", 36, UIF.IVORY)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := UIF.label("", 18, UIF.CREAM)
	body.name = "Body"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)
	vb.add_child(UIF.spacer(8))
	var retry := _button(&"restart_shift", "RETRY SHIFT")
	var to_title := _button(&"return_to_title", "RETURN TO TITLE")
	for b: Button in [retry, to_title]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(b)
	_centered_card(screen, card)
	screen.set_meta("initial_focus", retry)
	return screen


func _refresh_results() -> void:
	var text := _card_text("results")
	if text == null or game == null:
		return
	(text.get_node("Title") as Label).text = game.results_title()
	(text.get_node("Body") as Label).text = game.results_body()


func _build_credits() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.62))
	var card := UIF.dark_panel(22)
	var vb := UIF.column(8)
	card.add_child(vb)
	var title := UIF.label("CREDITS", 34, UIF.IVORY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for line in ["PIP THE PIZZA BOY", "a voxel delivery run on Marinara Way",
			"world, art and audio generated by the project's own tools",
			"built with Godot 4  ·  procedural everything, no external assets"]:
		var l := UIF.label(line, 17, UIF.CREAM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	vb.add_child(UIF.spacer(10))
	var back := _button(&"back", "BACK", 260.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(back)
	_centered_card(screen, card)
	screen.set_meta("initial_focus", back)
	return screen


func _build_confirm() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.7))
	var card := UIF.dark_panel(20)
	var vb := UIF.column(8)
	vb.name = "Text"
	card.add_child(vb)
	var title := UIF.label("RESTART THE RUN?", 26, UIF.IVORY)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := UIF.label("", 16, UIF.CREAM)
	body.name = "Body"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)
	vb.add_child(UIF.spacer(8))
	var row := UIF.row(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var no := _button(&"confirm_no", "KEEP PLAYING", 210.0, 42.0)
	var yes := _button(&"confirm_yes", "CONFIRM", 210.0, 42.0)
	row.add_child(no)
	row.add_child(yes)
	vb.add_child(row)
	_centered_card(screen, card)
	screen.set_meta("initial_focus", no)
	return screen


func _build_message() -> Control:
	var screen := Control.new()
	screen.add_child(UIF.dim(0.7))
	var card := UIF.dark_panel(20)
	var vb := UIF.column(8)
	vb.name = "Text"
	card.add_child(vb)
	var title := UIF.label("", 28, UIF.IVORY)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := UIF.label("", 17, UIF.CREAM)
	body.name = "Body"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)
	vb.add_child(UIF.spacer(8))
	var quit := _button(&"quit", "QUIT", 240.0)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(quit)
	_centered_card(screen, card)
	screen.set_meta("initial_focus", quit)
	return screen
