extends Node
## Only this input owner and the HUD run while paused; Game/world stay pausable.
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("pause") and game.is_shift_active():
		game._toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and (game.paused or not game.is_shift_active()):
		game.restart()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm") and game.state == game.State.TITLE:
		game.start_shift()
		get_viewport().set_input_as_handled()
	elif game.paused and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("interact"):
		if game.is_shift_active() and not game.paused:
			game.interact()
			get_viewport().set_input_as_handled()
