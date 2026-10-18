extends Control
## Phase 06 conversation screen. The DialogueService owns the conversation, the
## effects and the committed result; this screen only renders it and forwards
## presses, so a cancelled choice can never be mistaken for a committed one.
##
## MenuLayer treats it as one more pooled screen: the pause menu and options
## stack above it, and the world stays frozen for as long as the conversation or
## any menu over it is open.

const UIF = preload("res://scripts/ui/ui_factory.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")

var dialogue: Node
var _chip: ColorRect
var _speaker: Label
var _hint: Label
var _line: Label
var _choices: VBoxContainer
var _leave: Label
var _buttons: Array[Button] = []
var _choice_signature := ""
var _shown_line := ""


func setup(service: Node) -> void:
	dialogue = service
	dialogue.opened.connect(_on_changed)
	dialogue.updated.connect(_on_changed)
	dialogue.closed.connect(_on_closed)
	_build()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## MenuLayer refreshes live screens when they come to the top.
func refresh_values() -> void:
	_render()


func choice_buttons() -> Array[Button]:
	return _buttons.duplicate()


func line_text() -> String:
	return _line.text


func hint_text() -> String:
	return _hint.text


## Esc on the dialogue: an authored cancel when the conversation allows it.
## Transactional conversations return false, and the menu layer pauses above them
## instead of dropping them on the floor.
func handle_back() -> bool:
	if dialogue == null or not dialogue.active():
		return false
	return dialogue.cancel()


func _process(_delta: float) -> void:
	if dialogue != null and dialogue.active():
		_render()


func _on_changed(_event: Dictionary) -> void:
	_render()


func _on_closed(_event: Dictionary) -> void:
	_render()


func _build() -> void:
	add_child(UIF.dim(0.34))
	var card := UIF.dark_panel(20)
	var vb := UIF.column(8)
	vb.custom_minimum_size = Vector2(680, 0)
	card.add_child(vb)
	var row := UIF.row(10)
	_chip = ColorRect.new()
	_chip.name = "Chip"
	_chip.custom_minimum_size = Vector2(20, 20)
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chip)
	_speaker = UIF.label("", 21, UIF.GOLD, true)
	_speaker.name = "Speaker"
	_speaker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_speaker)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_hint = UIF.label("", 15, UIF.CREAM)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint)
	vb.add_child(row)
	_line = UIF.label("", 22, UIF.IVORY)
	_line.name = "Line"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(680, 92)
	vb.add_child(_line)
	_choices = UIF.column(6)
	_choices.name = "Choices"
	vb.add_child(_choices)
	_leave = UIF.label("", 15, UIF.CREAM)
	_leave.name = "Leave"
	_leave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_leave)
	UIF.centered(self, card, "Card")


func _render() -> void:
	if dialogue == null:
		return
	if not dialogue.active():
		_shown_line = ""
		_line.text = ""
		_rebuild_choices("")
		return
	# A menu stacked above the chat hides the screen; it must not fight that.
	if not is_visible_in_tree():
		return
	var speaker: Dictionary = dialogue.speaker()
	var colour := _colour(str(speaker.get("color", "")))
	_chip.color = colour
	_speaker.text = str(speaker.get("name", "")).to_upper()
	_speaker.add_theme_color_override("font_color", colour)
	var line: String = dialogue.visible_text()
	if line != _shown_line:
		_shown_line = line
		_line.text = line
	_hint.text = _hint_text()
	_leave.text = _leave_text()
	_rebuild_choices(_choice_key())
	_keep_choice_focus()


func _rebuild_choices(key: String) -> void:
	if key == _choice_signature:
		return
	_choice_signature = key
	for button in _buttons:
		_choices.remove_child(button)
		button.queue_free()
	_buttons.clear()
	if key.is_empty():
		return
	var labels: Array[String] = dialogue.choices()
	for i in range(labels.size()):
		var button := UIF.button(labels[i], 680, 20)
		button.name = "choice_%d" % i
		button.custom_minimum_size = Vector2(680, 44)
		button.pressed.connect(_on_choice.bind(i))
		_choices.add_child(button)
		_buttons.append(button)
	_keep_choice_focus()


## Choices are only reachable through a focused button, so whenever the chat is on
## top with nothing focused inside it (a menu just closed over it, a line just
## finished revealing) the first choice takes focus. The focus call is deferred and
## re-checked: rebuilding the buttons detaches the old ones, and a queued grab on a
## detached control is an error.
func _keep_choice_focus() -> void:
	if _buttons.is_empty() or not is_visible_in_tree():
		return
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner == null or not is_ancestor_of(owner):
		call_deferred("_focus_first_choice")


func _focus_first_choice() -> void:
	if _buttons.is_empty() or not is_inside_tree() or not is_visible_in_tree():
		return
	var first := _buttons[0]
	if not is_instance_valid(first) or not first.is_inside_tree():
		return
	first.grab_focus()


func _on_choice(index: int) -> void:
	if dialogue != null:
		dialogue.choose(index)


func _choice_key() -> String:
	if dialogue == null or not dialogue.active():
		return ""
	var labels: Array[String] = dialogue.choices()
	if labels.is_empty():
		return ""
	return "%d|%s|%d" % [dialogue.sessions(), dialogue.node_id, labels.size()]


func _hint_text() -> String:
	var key := InputBindings.prompt("interact")
	var enter := InputBindings.prompt("confirm")
	if not dialogue.choices().is_empty():
		return "UP / DOWN  CHOOSE     ·     %s / %s  PICK" % [key, enter]
	if dialogue.revealing():
		return "%s  SKIP" % key
	return "%s  CONTINUE" % key


func _leave_text() -> String:
	var key := InputBindings.prompt("pause")
	if dialogue.cancellable:
		return "%s  LEAVE THE CHAT  ·  nothing lost" % key
	return "%s  PAUSE OVER THE CHAT" % key


func _colour(html: String) -> Color:
	return Color(html) if not html.is_empty() else UIF.GOLD
