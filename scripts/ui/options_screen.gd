extends Control
## Options screen. Every row is generated from SettingsService.SPEC and writes
## straight through the service, which persists and applies each change. No
## option is decorative: sliders, choices and toggles all have live effect.

const UIF = preload("res://scripts/ui/ui_factory.gd")

var settings: Node
var on_back: Callable
var _rows: VBoxContainer
var _scroll: ScrollContainer


func setup(settings_node: Node, back: Callable) -> void:
	settings = settings_node
	on_back = back
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UIF.dim(0.66))
	var card := UIF.dark_panel(22)
	card.custom_minimum_size = Vector2(760, 0)
	UIF.centered(self, card)
	var column := UIF.column(8)
	card.add_child(column)
	var title := UIF.label("OPTIONS", 36, UIF.IVORY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_scroll = UIF.scroll(300)
	column.add_child(_scroll)
	_rows = UIF.column(6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	var footer := UIF.row(14)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	var reset := UIF.button("RESET TO DEFAULTS", 240, 18)
	reset.name = "btn_reset"
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)
	var back_button := UIF.button("BACK", 240, 18)
	back_button.name = "btn_back"
	back_button.pressed.connect(func() -> void: on_back.call())
	footer.add_child(back_button)
	_populate()
	# Remembered entry focus; MenuLayer re-grabs the last focused row on return.
	set_meta("initial_focus", reset)


func _populate() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	_fill_rows()


func _fill_rows() -> void:
	if not is_instance_valid(_rows):
		return
	var section := ""
	for spec in settings.SPEC:
		var key: String = spec.key
		var prefix: String = key.split("/")[0]
		if prefix != section:
			section = prefix
			var header := UIF.label(prefix.to_upper(), 22, UIF.GOLD)
			header.add_theme_constant_override("outline_size", 5)
			header.add_theme_color_override("font_outline_color", UIF.INK)
			_rows.add_child(header)
		_rows.add_child(_row(spec))


func _row(spec: Dictionary) -> Control:
	match str(spec.kind):
		"slider": return _slider_row(spec)
		"choice": return _choice_row(spec)
		"toggle": return _toggle_row(spec)
	return UIF.label("?" + str(spec.key), 16, UIF.RED)


func _row_label(spec: Dictionary, note := "") -> Label:
	var text: String = spec.label
	if not note.is_empty():
		text += "   " + note
	var label := UIF.label(text, 19, UIF.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _slider_row(spec: Dictionary) -> Control:
	var row := UIF.row(12)
	row.add_child(_row_label(spec))
	var slider := UIF.slider(spec.min, spec.max, spec.step)
	slider.name = "slider_" + str(spec.key).replace("/", "_")
	slider.value = float(settings.value(spec.key))
	var value_label := UIF.label(_slider_text(spec, slider.value), 18, UIF.GOLD)
	value_label.name = "value_" + str(spec.key).replace("/", "_")
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		settings.set_value(spec.key, v)
		value_label.text = _slider_text(spec, v))
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _slider_text(spec: Dictionary, value: float) -> String:
	if spec.get("percent", false):
		return "%d%%" % round(value * 100.0)
	return "%0.2f" % value


func _choice_row(spec: Dictionary) -> Control:
	var row := UIF.row(10)
	var note := ""
	var disabled := false
	if spec.get("needs_window", false) and DisplayServer.get_name() == "headless":
		disabled = true
		note = "desktop window only"
	row.add_child(_row_label(spec, note))
	var options: Array = spec.options
	var values: Array = spec.values
	var left := UIF.small_button("◀")
	var value_label := UIF.label("", 18, UIF.GOLD)
	value_label.custom_minimum_size = Vector2(150, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var right := UIF.small_button("▶")
	left.name = "left_" + str(spec.key).replace("/", "_")
	right.name = "right_" + str(spec.key).replace("/", "_")
	value_label.name = "value_" + str(spec.key).replace("/", "_")
	var current := _choice_index(values, settings.value(spec.key))
	value_label.text = options[current]
	left.disabled = disabled
	right.disabled = disabled
	left.pressed.connect(func() -> void:
		_step(spec, value_label, -1))
	right.pressed.connect(func() -> void:
		_step(spec, value_label, 1))
	row.add_child(left)
	row.add_child(value_label)
	row.add_child(right)
	return row


func _choice_index(values: Array, value: Variant) -> int:
	var best := 0
	for i in values.size():
		if values[i] == value:
			return i
		if float(values[i]) <= float(value):
			best = i
	return best


func _step(spec: Dictionary, label: Label, direction: int) -> void:
	var options: Array = spec.options
	var values: Array = spec.values
	var index := clampi(_choice_index(values, settings.value(spec.key)) + direction, 0, values.size() - 1)
	settings.set_value(spec.key, values[index])
	label.text = options[index]


func _toggle_row(spec: Dictionary) -> Control:
	var row := UIF.row(12)
	row.add_child(_row_label(spec))
	var button := UIF.toggle_button(bool(settings.value(spec.key)))
	button.name = "toggle_" + str(spec.key).replace("/", "_")
	button.pressed.connect(func() -> void:
		var on := not bool(settings.value(spec.key))
		settings.set_value(spec.key, on)
		UIF.refresh_toggle(button, on))
	row.add_child(button)
	return row


func _on_reset() -> void:
	settings.reset_to_defaults()
	_populate()


func refresh_values() -> void:
	_populate()


## Focus contract used by MenuLayer.focused_id().
func bindings() -> Array[Control]:
	var out: Array[Control] = []
	for child in _rows.get_children():
		for node in child.find_children("*", "Control", true, false):
			if (node as Control).focus_mode != Control.FOCUS_NONE:
				out.append(node)
	return out
