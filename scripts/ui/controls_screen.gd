extends Control
## Controls screen: live InputMap remapping with capture, conflict reporting and
## cancel. Esc always cancels a capture (never resumes the game from here), and
## critical movement actions can never end up unbound.

const UIF = preload("res://scripts/ui/ui_factory.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")

var settings: Node
var on_back: Callable
var _chips: Dictionary = {}
var _capturing := ""
var _status: Label


func setup(settings_node: Node, back: Callable) -> void:
	settings = settings_node
	on_back = back
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UIF.dim(0.66))
	var card := UIF.dark_panel(22)
	card.custom_minimum_size = Vector2(760, 0)
	UIF.centered(self, card)
	var column := UIF.column(8)
	card.add_child(column)
	var title := UIF.label("CONTROLS", 36, UIF.IVORY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var scroll := UIF.scroll(300)
	column.add_child(scroll)
	var rows := UIF.column(4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for action in settings.REMAPPABLE:
		rows.add_child(_action_row(action))
	_status = UIF.label("select a binding to change it  ·  esc cancels a capture", 17, UIF.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	var footer := UIF.row(14)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	var reset := UIF.button("RESET CONTROLS", 240, 18)
	reset.name = "btn_reset_controls"
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)
	var back_button := UIF.button("BACK", 240, 18)
	back_button.name = "btn_back"
	back_button.pressed.connect(func() -> void: on_back.call())
	footer.add_child(back_button)
	set_meta("initial_focus", back)


func _action_row(action: String) -> Control:
	var row := UIF.row(12)
	var label := UIF.label(InputBindings.LABELS.get(action, action.to_upper()), 18, UIF.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var chip := UIF.button(settings.binding_label(action), 280, 17)
	chip.name = "chip_" + action
	chip.custom_minimum_size = Vector2(280, 40)
	chip.pressed.connect(_begin_capture.bind(action))
	_chips[action] = chip
	row.add_child(chip)
	return row


func _begin_capture(action: String) -> void:
	_capturing = action
	for key in _chips:
		_chips[key].disabled = key != action
	_chips[action].text = "PRESS A KEY · MOUSE · PAD BUTTON"
	_status.text = "listening for %s  ·  esc cancels" % InputBindings.LABELS.get(action, action.to_upper())


func cancel_capture() -> void:
	if _capturing.is_empty():
		return
	var action := _capturing
	_capturing = ""
	_chips[action].text = settings.binding_label(action)
	_status.text = "kept %s on %s" % [InputBindings.LABELS.get(action, action.to_upper()), settings.binding_label(action)]
	for key in _chips:
		_chips[key].disabled = false


## Esc/back routing from MenuLayer: cancel an active capture first.
func handle_back() -> bool:
	if _capturing.is_empty():
		return false
	cancel_capture()
	return true


func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or event.is_echo():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE:
			cancel_capture()
		else:
			_assign(key)
	elif event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return
		get_viewport().set_input_as_handled()
		if pad.button_index == JOY_BUTTON_BACK:
			cancel_capture()
		else:
			_assign(pad)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		get_viewport().set_input_as_handled()
		_assign(mouse)


func _assign(event: InputEvent) -> void:
	var action := _capturing
	var clash: String = settings.set_binding(action, event)
	if clash.is_empty():
		_capturing = ""
		_status.text = "bound %s to %s" % [InputBindings.LABELS.get(action, action.to_upper()), settings.binding_label(action)]
		for key in _chips:
			_chips[key].disabled = false
	else:
		_status.text = "%s is already used by %s  ·  try another" % [
			InputBindings.event_label(event), InputBindings.LABELS.get(clash, clash.to_upper())]
	_chips[action].text = settings.binding_label(action)


func _on_reset() -> void:
	settings.reset_bindings()
	cancel_capture()
	_status.text = "controls reset to defaults"
	for key in _chips:
		_chips[key].text = settings.binding_label(key)
